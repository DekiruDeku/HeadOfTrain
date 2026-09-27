"""Record full B3 HTTP exchanges. Default: controlled SERVER clock, --real-time: UTC.

Always uses an isolated temporary DB and an actual local HTTP server. No testing
clock or time override endpoint is installed in the production server.
"""
import argparse
import json
import tempfile
import threading
import time
from pathlib import Path
from uuid import uuid4

try:
    from .server import make_server
    from .demo import request
except ImportError:
    from server import make_server
    from demo import request


class Demo:
    def __init__(self, server, real_time=False):
        self.server = server
        self.real_time = real_time
        self.ms = 1800000000000
        if not real_time:
            server.store.clock_ms = lambda: self.ms
        self.url = 'http://127.0.0.1:' + str(server.server_port)
        self.player = uuid4().hex
        self.trip = None
        self.exchanges = []

    def call(self, method, path, body=None, status=200):
        code, data = request(self.url, method, path, self.player, body)
        self.exchanges.append({'method': method, 'path': path, 'body': body, 'status': code, 'response': data})
        assert code == status, data
        if 'trip' in data:
            self.trip = data['trip']
        return data

    def start(self, condition='free'):
        self.call('POST', '/api/trips/start', {'request_id': uuid4().hex, 'simulation_mode': 'crew_b3', 'luggage_space': condition})

    def command(self, endpoint, **fields):
        return self.call('POST', '/api/trips/' + self.trip['trip_id'] + '/' + endpoint,
                         {'request_id': uuid4().hex, 'expected_state_version': self.trip['state_version'],
                          'incident_id': 'luggage-1', **fields})

    def wait(self, seconds):
        if self.real_time:
            time.sleep(seconds)
        else:
            self.ms += round(seconds * 1000)
        self.call('GET', '/api/trips/current')

    def action(self, action_id):
        return self.command('actions', node_id=self.trip['node_id'], action_id=action_id)

    def report(self):
        return self.call('GET', '/api/trips/' + self.trip['trip_id'] + '/report')['report']

    def finish(self, output, name):
        output.mkdir(parents=True, exist_ok=True)
        (output / (name + '.json')).write_text(json.dumps({
            'fixture_only': True, 'source': 'real HTTP responses',
            'clock': 'production UTC' if self.real_time else 'controlled server clock; no client elapsed',
            'player_id': self.player, 'exchanges': self.exchanges}, ensure_ascii=False, indent=2) + '\n')
        print(name + ': OK', flush=True)


def record(output, real_time=False):
    with tempfile.TemporaryDirectory(prefix='hot-b3-demo-') as tmp:
        server = make_server(port=0, db_path=Path(tmp) / 'demo.sqlite3')
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            cases = [('free', 'allow')] if real_time else [(condition, branch) for condition in ('free', 'occupied') for branch in ('help', 'demand', 'allow')]
            for condition, branch in cases:
                demo = Demo(server, real_time)
                demo.start(condition)
                demo.command('assignments', incident_id='blanket-1', staff_id='staff-1')
                demo.command('assignments', incident_id='table-1', staff_id='staff-2')
                demo.command('assignments', staff_id='staff-3')
                demo.command('dialog/open')
                demo.wait(1)
                assert demo.trip['paused']
                assert demo.trip['dialog']['critical_decision_time'] < 30
                demo.command('dialog/close')
                demo.wait(1)
                demo.command('dialog/open')
                actions = {'allow': ['allow_luggage'], 'demand': ['demand_removal', 'repeat_demand'],
                           'help': ['offer_help', 'place_free', 'confirm_clear'] if condition == 'free' else
                                   ['offer_help', 'check_alternative', 'place_alternative', 'confirm_clear']}[branch]
                for action in actions:
                    demo.action(action)
                demo.wait(24)
                result = demo.report()
                assert [i['resolution'] for i in result['incidents'][1:]] == ['served', 'served']
                assert result['scales']['safety'] == (80 if branch == 'allow' else 100)
                assert result['scales']['loyalty'] == {'luggage-owner': {'allow':54,'demand':40,'help':58}[branch], 'blanket-passenger':58, 'table-passenger':56}
                demo.finish(output, condition + '-' + branch)
            if real_time:
                return
            demo = Demo(server)
            demo.start()
            demo.command('assignments', staff_id='staff-1')
            demo.wait(10)
            assert demo.trip['staff'][0]['position']['to'] == 'c2-door'
            demo.wait(8)
            demo.command('dialog/open')
            demo.wait(10)
            demo.command('dialog/close')
            demo.wait(5)
            demo.command('dialog/open')
            demo.wait(35)
            assert demo.trip['outcome'] == 'decision_timeout'
            assert demo.trip['simulation_time'] == 43
            demo.wait(100)
            demo.report()
            demo.finish(output, 'cross-carriage-critical-timeout')
            demo = Demo(server)
            demo.start()
            demo.wait(60)
            assert demo.trip['outcome'] == 'response_timeout'
            demo.wait(40)
            demo.report()
            demo.finish(output, 'reaction-timeouts')
        finally:
            server.shutdown()
            thread.join(timeout=5)
            server.server_close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--record', type=Path, required=True)
    parser.add_argument('--real-time', action='store_true')
    args = parser.parse_args()
    record(args.record, args.real_time)
