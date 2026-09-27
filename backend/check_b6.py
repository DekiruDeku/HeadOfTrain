"""Run a full trip against an isolated COPY of production server, using real time.

No injected clock, no test endpoints, no working database access. Takes ~7:30.
Records HTTP exchanges, restarts, backup/restore and final report/profile/ranks.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from uuid import uuid4

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from backend.b4_paths import correct_actions
from backend.database import snapshot


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


class Check:
    def __init__(self, output):
        self.output = output.resolve()
        self.output.mkdir(parents=True, exist_ok=False)
        self.copy = self.output / 'project'
        shutil.copytree(Path(__file__).parent, self.copy / 'backend',
                        ignore=shutil.ignore_patterns('var', '__pycache__', '*.pyc'))
        self.db = self.output / 'data' / 'clean.sqlite3'
        self.player = uuid4().hex
        self.process = None
        self.exchanges = []
        self.restarts = []
        self.log = None

    def launch(self):
        log_path = self.output / ('server-' + str(len(self.restarts)) + '.log')
        self.log = log_path.open('wb')
        self.process = subprocess.Popen([sys.executable, '-u', str(self.copy / 'backend/server.py'),
                                        '--host', '127.0.0.1', '--port', '0', '--db', str(self.db)],
                                       cwd=self.copy, stdout=self.log, stderr=self.log)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            lines = log_path.read_text().splitlines()
            if len(lines) >= 3 and lines[0].startswith('Game: '):
                self.url = lines[0][6:].rstrip('/')
                self.restarts.append({'pid': self.process.pid, 'db': str(self.db), 'url': self.url})
                self.call('GET', '/api/health')
                return
            if self.process.poll() is not None:
                raise RuntimeError(log_path.read_text())
            time.sleep(.05)
        raise TimeoutError('Server startup timeout')

    def stop(self):
        if self.process is not None:
            if self.process.poll() is None:
                self.process.kill()
            self.process.wait(timeout=10)
            self.process = None
        if self.log is not None:
            self.log.close()
            self.log = None

    def call(self, method, path, body=None, status=200):
        req = Request(self.url + path, method=method,
                      data=json.dumps(body).encode() if body is not None else None,
                      headers={'X-Demo-Player': self.player, 'Content-Type': 'application/json'})
        try:
            reply = urlopen(req, timeout=10)
        except HTTPError as error:
            reply = error
        with reply:
            data = json.load(reply)
            self.exchanges.append(dict(method=method, path=path, body=body, status=reply.status, response=data))
            assert reply.status == status, data
        assert data['api_version'] == 'v1'
        if 'trip' in data:
            self.trip = data['trip']
        return data

    def get(self):
        return self.call('GET', '/api/trips/current')['trip']

    def command(self, op, incident, **fields):
        self.get()
        body = dict(request_id=uuid4().hex, expected_state_version=self.trip['state_version'],
                    incident_id=incident, **fields)
        path = '/api/trips/' + self.trip['trip_id'] + '/' + op
        result = self.call('POST', path, body)
        # Simulate retry after an uncertain response: expect byte-equivalent JSON.
        assert self.call('POST', path, body) == result
        return body, result

    def until(self, target):
        deadline = time.monotonic() + 400
        while self.get()['simulation_time'] < target:
            assert time.monotonic() < deadline, 'Trip stopped advancing'
            time.sleep(min(2, max(.05, target - self.trip['simulation_time'])))

    def solve(self, incident, actions, restart=False):
        self.command('dialog/open', incident)
        for idx, action in enumerate(actions):
            time.sleep(10)  # Actual wall-clock reading allowance, not a clock jump.
            body, result = self.command('actions', incident, node_id=self.trip['dialog']['node_id'], action_id=action)
            if restart and idx == 0:
                before = self.trip
                self.stop()
                self.launch()
                restored = self.get()
                assert restored['active_dialog_id'] == before['active_dialog_id']
                assert restored['simulation_time'] == before['simulation_time']
                assert restored['history'] == before['history']
                assert self.call('POST', '/api/trips/' + self.trip['trip_id'] + '/actions', body) == result

    def run(self):
        began = time.monotonic()
        self.launch()
        empty = self.call('GET', '/api/profile')['profile']
        assert empty['total_points'] == 0 and empty['report_ids'] == []
        self.call('POST', '/api/trips/start', dict(request_id='b6-start', simulation_mode='full_b4'))
        actions = correct_actions(self.trip['conditions'])
        self.command('assignments', 'blanket-1', staff_id='staff-1')
        self.command('assignments', 'luggage-1', staff_id='staff-3')
        self.solve('luggage-1', actions['luggage-1'], restart=True)
        print('PASS: active dialog restored after hard process restart; exact action retry', flush=True)
        self.until(100)
        self.command('assignments', 'children-1', staff_id='staff-1')
        self.solve('children-1', actions['children-1'])
        self.until(200)
        self.command('assignments', 'table-1', staff_id='staff-2')
        self.until(260)
        self.command('assignments', 'seat-1', staff_id='staff-2')
        self.solve('seat-1', actions['seat-1'])
        self.until(360)
        elapsed = time.monotonic() - began
        assert self.trip['outcome'] == 'successful'
        assert len(self.trip['incidents']) == 5
        tid = self.trip['trip_id']
        report = self.call('GET', '/api/trips/' + tid + '/report')['report']
        profile = self.call('GET', '/api/profile')['profile']
        notifications = self.call('GET', '/api/notifications')
        assert report['points']['earned'] == report['points']['awarded'] == profile['total_points'] == 170
        assert sum(c['points'] for c in report['competencies']) == 170
        assert report['scales'] == self.trip['scales']
        assert len(report['achievements_unlocked']) == 3 and notifications['total'] == 1
        ranks = {scope: self.call('GET', '/api/leaderboard?scope=' + scope) for scope in ('crew', 'depot', 'company')}
        assert all(r['entries'][0]['total_points'] == 170 and r['entries'][0]['is_self'] for r in ranks.values())
        backup = self.output / 'backup.sqlite3'
        backup_check = snapshot(self.db, backup)  # Server is still running.
        self.stop()
        self.launch()
        assert self.call('GET', '/api/trips/' + tid + '/report')['report'] == report
        assert self.call('GET', '/api/profile')['profile'] == profile
        self.stop()
        self.db = self.output / 'restored' / 'demo.sqlite3'
        restore_check = snapshot(backup, self.db)
        self.launch()
        for request_id in ('complete-one', 'complete-one', 'complete-two'):
            assert self.call('POST', '/api/trips/' + tid + '/complete', {'request_id': request_id})['report'] == report
        assert self.call('GET', '/api/profile')['profile'] == profile
        assert self.call('GET', '/api/notifications') == notifications
        for scope, rank in ranks.items():
            assert self.call('GET', '/api/leaderboard?scope=' + scope) == rank
        write(self.output / 'report.json', report)
        write(self.output / 'profile.json', profile)
        write(self.output / 'results.json', dict(passed=True, clock='production_wall_clock', wall_seconds=round(elapsed, 3),
            simulation_seconds=360, earned=170, active_restart=True, completed_restart=True, restore_equal=True,
            idempotency=True, backup=backup_check, restore=restore_check, processes=self.restarts,
            browser_tested=False, human_readability_tested=False, player_id=self.player, trip_id=tid))
        print('PASS: real full trip, 170 points, three rankings, restart, live backup and restore', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='Must not exist')
    check = Check(parser.parse_args().output)
    try:
        check.run()
    finally:
        check.stop()
        write(check.output / 'http-exchanges.json', check.exchanges)


if __name__ == '__main__':
    main()
