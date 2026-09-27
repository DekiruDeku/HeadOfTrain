"""B2: route semantics, actual missing replies, process death and concurrent writes."""
import json
import select
import queue
import socket
import sqlite3
from contextlib import closing
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import urlsplit
from uuid import uuid4

from backend.b2_paths import cases, render
from backend.demo import request
from backend.storage import Store

ROOT = Path(__file__).resolve().parents[2]
CONFIG = json.loads((ROOT / 'backend/data/luggage-v1.json').read_text(encoding='utf-8'))


class ServerCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.db = Path(self.temp.name) / 'test.sqlite3'
        self.log_path = Path(self.temp.name) / 'server.log'
        self.log = self.log_path.open('ab', buffering=0)
        self.addCleanup(self.log.close)
        self.process = None
        self.addCleanup(self.stop)
        self.player = uuid4().hex
        self.launch()

    def launch(self, gated=False):
        script = 'backend/tests/fault_server.py' if gated else 'backend/server.py'
        cmd = [sys.executable, '-u', str(ROOT / script), '--db', str(self.db)]
        if not gated:
            cmd += ['--port', '0']
        self.process = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.log, bufsize=0)
        line = self.control_line()
        self.assertTrue(line.startswith('Game: '), line)
        self.url = line.removeprefix('Game: ').rstrip('/')
        if not gated:
            self.control_line()
            self.control_line()

    def control_line(self):
        # Windows select() supports sockets only; read the control pipe in a
        # bounded worker instead. One call consumes exactly one line on all OSes.
        result = queue.Queue()
        stream = self.process.stdout
        def read_line():
            try:
                result.put(stream.readline())
            except OSError as error:
                result.put(error)
        worker = threading.Thread(target=read_line, daemon=True)
        worker.start()
        try:
            line = result.get(timeout=10)
        except queue.Empty:
            self.fail('Timed out waiting for server control line')
        if isinstance(line, Exception):
            raise line
        self.assertTrue(line, self.log_path.read_text(errors='replace'))
        worker.join(timeout=1)
        return line.decode().strip()

    def stop(self, hard=False):
        if self.process is not None:
            if self.process.poll() is None:
                (self.process.kill if hard else self.process.terminate)()
                self.process.wait(timeout=10)
            self.process.stdout.close()
            self.process.stdin.close()
            self.process = None

    def call(self, method, path, body=None, status=200, player=None):
        code, result = request(self.url, method, path, player or self.player, body)
        self.assertEqual(code, status, result)
        return result

    def start(self, condition='free', **fields):
        return self.call('POST', '/api/trips/start', dict(request_id=uuid4().hex, luggage_space=condition, **fields))['trip']

    def body(self, trip, action, **fields):
        return dict(request_id=uuid4().hex, expected_state_version=trip['state_version'], incident_id='luggage-1', node_id=trip['node_id'], action_id=action, **fields)

    def act(self, trip, action):
        return self.call('POST', '/api/trips/' + trip['trip_id'] + '/actions', self.body(trip, action))['trip']

    def saved(self):
        with closing(sqlite3.connect(self.db)) as db, db:
            return {table: db.execute('SELECT * FROM ' + table + ' ORDER BY 1,2').fetchall() for table in ('players', 'trips', 'requests')}

    def assert_disconnected(self, sock):
        try:
            self.assertEqual(sock.recv(4096), b'')
        except ConnectionResetError:
            pass  # Windows reports a killed peer as RST, Unix commonly as EOF.

    def held_request(self, path, body, expected='COMMITTED'):
        address = urlsplit(self.url)
        sock = socket.create_connection((address.hostname, address.port), timeout=10)
        self.addCleanup(sock.close)
        payload = json.dumps(body).encode()
        headers = f'POST {path} HTTP/1.1\r\nHost: localhost\r\nX-Demo-Player: {self.player}\r\nX-Test-Hold-Response: yes\r\nContent-Type: application/json\r\nContent-Length: {len(payload)}\r\nConnection: close\r\n\r\n'
        sock.sendall(headers.encode() + payload)
        self.assertEqual(self.control_line(), expected)
        # The handler reached the gate but has sent neither headers nor body.
        self.assertEqual(select.select([sock], [], [], 0)[0], [])
        return sock


class PathTests(ServerCase):
    def exercise(self, case):
        trip = self.start(case['condition'])
        path = '/api/trips/' + trip['trip_id']
        self.assertEqual(trip['scales'], CONFIG['initial_scales'])
        loyalty, safety, facts, marks = 50, 100, {'aisle_clear': False, 'placement': None}, []
        expected_history = []
        for index, (before, aid, after) in enumerate(case['edges'], 1):
            self.assertEqual(trip['node_id'], before)
            action = next(a for a in CONFIG['nodes'][before]['actions'] if a['id'] == aid)
            body = self.body(trip, aid)
            response = self.call('POST', path + '/actions', body)
            trip = response['trip']
            effects = action['effects']
            loyalty += effects.get('loyalty_delta', 0)
            safety += effects.get('safety_delta', 0)
            facts.update(effects.get('facts', {}))
            marks = list(dict.fromkeys(marks + effects.get('critical_marks', [])))
            expected_history.append(dict(request_id=body['request_id'], action_id=aid, incident_id='luggage-1', node_before=before, node_after=after, selected_text=action['text'], effects=effects, explanation=action['explanation'], explanation_status=action['explanation_status']))
            self.assertEqual(trip['node_id'], after)
            self.assertEqual(trip['state_version'], index + 1)
            self.assertEqual(trip['facts'], facts)
            self.assertEqual(trip['critical_marks'], marks)
            self.assertEqual(trip['scales']['loyalty']['luggage-owner'], loyalty)
            self.assertEqual(trip['scales']['safety'], safety)
            self.assertEqual(trip['conditions'], {'luggage_space': case['condition']})
            self.assertEqual(len(trip['history']), index)
            for actual, expected in zip(trip['history'], expected_history):
                self.assertGreaterEqual(actual['decision_time_seconds'], 0)
                self.assertTrue(actual['decided_at'])
                self.assertEqual({k: v for k, v in actual.items() if k not in ('decided_at', 'decision_time_seconds')}, expected)
            self.assertEqual(self.call('POST', path + '/actions', body), response)
            self.assertEqual(self.call('GET', path)['trip'], trip)
            if index < len(case['edges']):
                self.assertFalse(response['report_available'])
                self.assertIsNone(trip['scales']['overall_loyalty'])
                self.assertEqual(self.call('GET', path + '/report', status=409)['error'], 'report_not_ready')
        self.assertEqual(trip['status'], 'completed')
        self.assertIsNone(trip['dialog'])
        self.assertIsNone(trip['active_dialog_id'])
        self.assertEqual(trip['outcome'], case['outcome'])
        self.assertEqual(trip['scales']['loyalty']['luggage-owner'], case['loyalty'])
        self.assertEqual(trip['scales']['overall_loyalty'], case['loyalty'])
        self.assertEqual(trip['scales']['safety'], case['safety'])
        self.assertEqual(trip['facts']['placement'], case['placement'])
        self.assertEqual(trip['facts']['aisle_clear'], case['clear'])
        report = self.call('GET', path + '/report')['report']
        for key in ('history', 'scales', 'facts', 'critical_marks', 'outcome', 'state_version', 'completed_at'):
            self.assertEqual(report[key], trip[key])
        ending = CONFIG['nodes'][trip['node_id']]
        self.assertEqual(report['summary'], ending['text'])
        self.assertEqual(report['recommendation'], ending['recommendation'])
        snapshot = self.saved()
        self.assertEqual(self.call('POST', path + '/actions', self.body(trip, 'offer_help'), status=409)['error'], 'trip_completed')
        self.assertEqual(self.saved(), snapshot)

    def test_route_inventory_and_document_match_config(self):
        self.assertEqual(len(cases()), 20)
        reached = set()
        for condition in ('free', 'occupied'):
            def walk(node, prefix=()):
                data = CONFIG['nodes'][node]
                if 'branches' in data:
                    matches = [b for b in data['branches'] if b['conditions']['luggage_space'] == condition]
                    self.assertEqual(len(matches), 1)
                    return walk(matches[0]['next'], prefix)
                if 'outcome' in data:
                    reached.add((condition, prefix))
                    return
                self.assertLess(len(prefix), 10, 'Unexpected cycle')
                for a in data['actions']:
                    if all({'luggage_space': condition}.get(k) == v for k, v in a['conditions'].items()):
                        walk(a['next'], prefix + (a['id'],))
            walk('opening')
        expected = {(c['condition'], tuple(e[1] for e in c['edges'])) for c in cases()}
        self.assertEqual(reached, expected)
        self.assertEqual((ROOT / 'docs/content/b2-paths.md').read_text(encoding='utf-8'), render())


for case in cases():
    def test(self, case=case):
        self.exercise(case)
    setattr(PathTests, 'test_path_' + case['id'].replace('-', '_'), test)


class ReliabilityTests(ServerCase):
    def test_no_reply_after_commit_then_hard_restart(self):
        for stage in ('start', 'intermediate', 'terminal_gain', 'terminal_loss'):
            with self.subTest(stage=stage):
                self.player = uuid4().hex
                self.stop()
                self.launch(gated=True)
                if stage == 'start':
                    path = '/api/trips/start'
                    body = {'request_id': 'lost-start', 'luggage_space': 'occupied'}
                else:
                    trip = self.start()
                    if stage == 'terminal_gain':
                        trip = self.act(self.act(trip, 'offer_help'), 'place_free')
                    action = {'intermediate': 'offer_help', 'terminal_gain': 'confirm_clear', 'terminal_loss': 'allow_luggage'}[stage]
                    path = '/api/trips/' + trip['trip_id'] + '/actions'
                    body = self.body(trip, action)
                sock = self.held_request(path, body)
                with closing(sqlite3.connect(self.db)) as db, db:
                    saved_response = json.loads(db.execute('SELECT response_json FROM requests WHERE player_id=? AND request_id=?', (self.player, body['request_id'])).fetchone()[0])
                snapshot = self.saved()
                self.stop(hard=True)
                self.assert_disconnected(sock)
                sock.close()
                self.launch()
                for _ in range(2):
                    self.assertEqual(self.call('POST', path, body), saved_response)
                self.assertEqual(self.saved(), snapshot)
                current = self.call('GET', '/api/trips/current')['trip']
                self.assertEqual(current, saved_response['trip'])
                if stage.startswith('terminal'):
                    report = self.call('GET', '/api/trips/' + current['trip_id'] + '/report')['report']
                    self.assertEqual(report['history'], current['history'])
                    self.assertEqual(report['scales']['loyalty']['luggage-owner'], 58 if stage == 'terminal_gain' else 54)
                    self.assertEqual(report['scales']['safety'], 100 if stage == 'terminal_gain' else 80)

    def test_peer_reset_after_commit_does_not_escape_handler(self):
        self.stop()
        self.launch(gated=True)
        trip = self.start()
        path = '/api/trips/' + trip['trip_id'] + '/actions'
        body = self.body(trip, 'allow_luggage')
        sock = self.held_request(path, body)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
        sock.close()  # RST while server has committed, but sent no HTTP bytes.
        self.process.stdin.write(b'release\n')
        self.process.stdin.flush()
        self.assertEqual(self.control_line(), 'HANDLER_DONE', self.log_path.read_text())
        replay = self.call('POST', path, body)
        self.assertEqual(len(replay['trip']['history']), 1)
        self.stop()
        log = self.log_path.read_text()
        self.assertNotIn('Traceback', log)
        self.assertIn('Client disconnected', log)

    def test_hard_crash_before_commit_rolls_back_everything(self):
        self.stop()
        self.launch(gated=True)
        trip = self.start()
        path = '/api/trips/' + trip['trip_id'] + '/actions'
        body = {**self.body(trip, 'allow_luggage'), 'request_id': 'hold-before-commit'}
        before = self.saved()
        sock = self.held_request(path, body, expected='UNCOMMITTED')
        self.assertEqual(self.saved(), before)  # Reader cannot see in-flight changes.
        self.stop(hard=True)
        self.assert_disconnected(sock)
        self.launch()
        self.assertEqual(self.saved(), before)
        applied = self.call('POST', path, body)
        self.assertEqual(applied['trip']['scales']['safety'], 80)
        self.assertEqual(len(applied['trip']['history']), 1)
        self.assertEqual(self.call('POST', path, body), applied)

    def test_http_storage_failure_rolls_back_report_and_allows_same_retry(self):
        trip = self.start()
        path = '/api/trips/' + trip['trip_id'] + '/actions'
        body = self.body(trip, 'allow_luggage')
        before = self.saved()
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("CREATE TRIGGER fail_record BEFORE INSERT ON requests BEGIN SELECT RAISE(ABORT, 'B2 fault'); END")
        self.assertEqual(self.call('POST', path, body, status=503)['error'], 'storage_unavailable')
        self.assertEqual(self.saved(), before)
        self.assertEqual(self.call('GET', path.removesuffix('/actions') + '/report', status=409)['error'], 'report_not_ready')
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute('DROP TRIGGER fail_record')
        self.stop()
        self.launch()
        result = self.call('POST', path, body)
        self.assertEqual(result['trip']['scales']['safety'], 80)
        self.assertEqual(self.call('POST', path, body), result)

    def test_failed_start_leaves_no_orphan_player_trip_or_request(self):
        before = self.saved()
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("CREATE TRIGGER fail_record BEFORE INSERT ON requests BEGIN SELECT RAISE(ABORT, 'B2 start fault'); END")
        body = {'request_id': 'start-after-failure', 'luggage_space': 'occupied'}
        self.assertEqual(self.call('POST', '/api/trips/start', body, status=503)['error'], 'storage_unavailable')
        self.assertEqual(self.saved(), before)
        self.assertEqual(self.call('GET', '/api/trips/current', status=404)['error'], 'no_current_trip')
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute('DROP TRIGGER fail_record')
        started = self.call('POST', '/api/trips/start', body)
        self.assertEqual(self.call('POST', '/api/trips/start', body), started)
        self.assertEqual([len(rows) for rows in self.saved().values()], [1, 1, 1])

    def test_rejected_requests_leave_all_tables_unchanged(self):
        trip = self.start('occupied')
        trip = self.act(trip, 'offer_help')
        path = '/api/trips/' + trip['trip_id'] + '/actions'
        valid = self.body(trip, 'check_alternative')
        before = self.saved()
        for fields, status, error in [({'action_id': 'place_free'}, 422, 'action_unavailable'), ({'action_id': 'unknown'}, 422, 'invalid_action'), ({'node_id': 'alternative'}, 422, 'invalid_node'), ({'incident_id': 'other'}, 422, 'invalid_incident'), ({'expected_state_version': 1}, 409, 'state_version_conflict'), ({'expected_state_version': True}, 400, 'invalid_state_version'), ({'scales': {'safety': 100}}, 400, 'invalid_fields')]:
            with self.subTest(error=error):
                self.assertEqual(self.call('POST', path, {**valid, **fields}, status=status)['error'], error)
                self.assertEqual(self.saved(), before)
        self.assertEqual(self.call('POST', path, valid, status=404, player=uuid4().hex)['error'], 'trip_not_found')
        self.assertEqual(self.saved(), before)
        self.assertEqual(self.call('POST', path, valid)['trip']['node_id'], 'alternative')

    def test_old_success_replay_never_rewinds_new_attempt(self):
        trip = self.start()
        path = '/api/trips/' + trip['trip_id'] + '/actions'
        body = self.body(trip, 'offer_help')
        old_response = self.call('POST', path, body)
        done = self.act(old_response['trip'], 'allow_luggage')
        old_report = self.call('GET', path.removesuffix('/actions') + '/report')
        fresh = self.start('occupied', new_attempt=True)
        before = self.saved()
        self.stop()
        self.launch()
        self.assertEqual(self.call('POST', path, dict(reversed(list(body.items())))), old_response)
        self.assertEqual(self.call('GET', '/api/trips/current')['trip'], fresh)
        self.assertEqual(self.call('GET', path.removesuffix('/actions'))['trip'], done)
        self.assertEqual(self.call('GET', path.removesuffix('/actions') + '/report'), old_report)
        self.assertEqual(self.saved(), before)
        conflict = {**self.body(fresh, 'offer_help'), 'request_id': body['request_id']}
        self.assertEqual(self.call('POST', '/api/trips/' + fresh['trip_id'] + '/actions', conflict, status=409)['error'], 'request_id_conflict')

    def race(self, path, bodies):
        barrier = threading.Barrier(len(bodies))
        def send(body):
            barrier.wait(timeout=10)
            return request(self.url, 'POST', path, self.player, body)
        with ThreadPoolExecutor(max_workers=len(bodies)) as pool:
            return list(pool.map(send, bodies))

    def test_synchronized_terminal_races_and_durable_winner(self):
        for mode in ('duplicate', 'competing', 'id_collision'):
            for iteration in range(5):
                with self.subTest(mode=mode, iteration=iteration):
                    self.player = uuid4().hex
                    trip = self.act(self.act(self.start(), 'offer_help'), 'place_free')
                    path = '/api/trips/' + trip['trip_id'] + '/actions'
                    first = self.body(trip, 'confirm_clear')
                    second = first.copy() if mode == 'duplicate' else self.body(trip, 'finish_unchecked')
                    if mode == 'id_collision':
                        second['request_id'] = first['request_id']
                    results = self.race(path, [first, second])
                    if mode == 'duplicate':
                        self.assertEqual(results[0], results[1])
                        self.assertEqual(results[0][0], 200)
                    else:
                        self.assertEqual(sorted(r[0] for r in results), [200, 409])
                        error = next(r[1]['error'] for r in results if r[0] == 409)
                        self.assertEqual(error, 'request_id_conflict' if mode == 'id_collision' else 'state_version_conflict')
                    winner = next(r[1] for r in results if r[0] == 200)
                    current = self.call('GET', '/api/trips/current')['trip']
                    self.assertEqual(current, winner['trip'])
                    self.assertEqual(current['state_version'], 4)
                    self.assertEqual(len(current['history']), 3)
                    aid = current['history'][-1]['action_id']
                    self.assertEqual(current['scales']['loyalty']['luggage-owner'], 58 if aid == 'confirm_clear' else 50)
                    report = self.call('GET', path.removesuffix('/actions') + '/report')['report']
                    self.assertEqual(report['history'], current['history'])
                    self.assertEqual(report['scales'], current['scales'])
                    with closing(sqlite3.connect(self.db)) as db, db:
                        self.assertEqual(db.execute('SELECT count(*) FROM requests WHERE player_id=?', (self.player,)).fetchone()[0], 4)
                    self.stop()
                    self.launch()
                    self.assertEqual(self.call('GET', '/api/trips/current')['trip'], current)
                    for body, result in zip([first, second], results):
                        self.assertEqual(request(self.url, 'POST', path, self.player, body), result)

    def test_synchronized_new_attempt_start_and_request_id_scope(self):
        for same_id in (False, True):
            self.player = uuid4().hex
            old = self.act(self.start(), 'allow_luggage')
            one = {'request_id': 'new', 'luggage_space': 'occupied', 'new_attempt': True}
            two = {**one, 'request_id': 'new' if same_id else 'other'}
            results = self.race('/api/trips/start', [one, two])
            self.assertEqual(sorted(r[0] for r in results), [200, 200] if same_id else [200, 409])
            if same_id:
                self.assertEqual(results[0], results[1])
            else:
                self.assertEqual(next(r[1]['error'] for r in results if r[0] == 409), 'active_trip_exists')
            current = self.call('GET', '/api/trips/current')['trip']
            self.assertNotEqual(current['trip_id'], old['trip_id'])
            self.assertEqual(current['state_version'], 1)
            with closing(sqlite3.connect(self.db)) as db, db:
                self.assertEqual(db.execute('SELECT count(*) FROM trips WHERE player_id=?', (self.player,)).fetchone()[0], 2)
            # Same request_id is independent for different player identities.
            another = self.call('POST', '/api/trips/start', one, player=uuid4().hex)['trip']
            self.assertNotEqual(another['trip_id'], current['trip_id'])

    def test_pinned_content_and_report_survive_source_change_and_restart(self):
        store = Store(self.db)
        original = self.start()
        store.scenario['version'] = 'test-content-change'
        action = store.scenario['nodes']['opening']['actions'][2]
        action['effects']['safety_delta'] = -99
        action['explanation'] = 'Test-only replacement'
        body = self.body(original, 'allow_luggage')
        path = '/api/trips/' + original['trip_id'] + '/actions'
        response = store.mutate(self.player, path, body, original['trip_id'])
        self.assertEqual(response['trip']['scales']['safety'], 80)
        self.assertEqual(response['trip']['scenario_version'], CONFIG['version'])
        self.assertEqual(response['trip']['history'][0]['explanation'], CONFIG['nodes']['opening']['actions'][2]['explanation'])
        report = self.call('GET', path.removesuffix('/actions') + '/report')
        self.stop()
        self.launch()
        self.assertEqual(self.call('GET', path.removesuffix('/actions') + '/report'), report)
        self.assertEqual(self.call('POST', path, body), response)


if __name__ == '__main__':
    unittest.main()
