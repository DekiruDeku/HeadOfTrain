import http.cookiejar
import json
import sqlite3
from contextlib import closing
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import Request, build_opener, HTTPCookieProcessor, urlopen
from uuid import uuid4

from backend.demo import request, run_fixture, run_errors
from backend.storage import Store

ROOT = Path(__file__).resolve().parents[2]


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db = Path(self.temp.name) / 'attempts.sqlite3'
        self.player = uuid4().hex
        self.launch()

    def launch(self):
        self.process = subprocess.Popen([sys.executable, str(ROOT / 'backend/server.py'), '--port', '0', '--db', str(self.db)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        line = self.process.stdout.readline().strip()
        if not line.startswith('Game: '):
            raise RuntimeError('Server did not start: ' + line)
        self.url = line.removeprefix('Game: ').rstrip('/')

    def stop(self):
        self.process.terminate()
        self.process.wait(timeout=10)
        self.process.stdout.close()

    def tearDown(self):
        self.stop()
        self.temp.cleanup()

    def call(self, method, path, body=None, status=200, player=None):
        code, data = request(self.url, method, path, player or self.player, body)
        self.assertEqual(code, status, data)
        return data

    def start(self, condition='free'):
        return self.call('POST', '/api/trips/start', {'request_id': uuid4().hex, 'luggage_space': condition})['trip']

    def action(self, trip, action_id, **overrides):
        return {'request_id': uuid4().hex, 'expected_state_version': trip['state_version'], 'incident_id': 'luggage-1', 'node_id': trip['node_id'], 'action_id': action_id, **overrides}

    def test_six_fixture_paths(self):
        for fixture in sorted((ROOT / 'docs/api/fixtures').glob('*.json')):
            with self.subTest(fixture=fixture.name):
                run_fixture(self.url, json.loads(fixture.read_text()))

    def test_documented_error_examples(self):
        run_errors(self.url)

    def test_legacy_start_cookie_and_restore(self):
        jar = http.cookiejar.CookieJar()
        opener = build_opener(HTTPCookieProcessor(jar))
        def start():
            with opener.open(Request(self.url + '/api/trips/start', b'{}', {'Content-Type': 'application/json'})) as r:
                return json.load(r)
        first, second = start(), start()
        self.assertTrue(first['ok'])
        self.assertEqual(first['status'], 'started')
        self.assertEqual(first['trip_id'], second['trip_id'])
        self.assertTrue(second['resumed'])
        self.assertEqual(len(list(jar)), 1)
        with opener.open(self.url + '/api/trips/current') as r:
            self.assertEqual(json.load(r)['trip']['trip_id'], first['trip_id'])

    def test_identity_ownership_and_missing(self):
        trip = self.start()
        self.call('GET', '/api/trips/' + trip['trip_id'], player=uuid4().hex, status=404)
        self.call('GET', '/api/trips/current', player=uuid4().hex, status=404)
        self.call('GET', '/api/trips/current', player='invalid', status=400)
        from urllib.error import HTTPError
        with self.assertRaises(HTTPError) as context:
            urlopen(Request(self.url + '/api/trips/start', b'{"request_id":"first"}', {'Content-Type': 'application/json'}))
        self.assertEqual(context.exception.code, 401)
        context.exception.close()

    def test_unknown_foreign_node_and_condition_actions(self):
        trip = self.start('occupied')
        path = '/api/trips/' + trip['trip_id']
        for body in [self.action(trip, 'unknown'), self.action(trip, 'place_free'), self.action(trip, 'allow_luggage', node_id='conflict'), self.action(trip, 'offer_help', incident_id='other')]:
            self.call('POST', path + '/actions', body, status=422)
            self.assertEqual(self.call('GET', path)['trip'], trip)
        trip = self.call('POST', path + '/actions', self.action(trip, 'offer_help'))['trip']
        self.assertEqual(trip['node_id'], 'space_occupied')
        self.assertFalse(next(o for o in trip['dialog']['options'] if o['id'] == 'place_free')['available'])
        result = self.call('POST', path + '/actions', self.action(trip, 'place_free'), status=422)
        self.assertEqual(result['error'], 'action_unavailable')
        self.assertEqual(self.call('GET', path)['trip'], trip)

    def test_replay_conflicts_and_version_order(self):
        trip = self.start()
        path = '/api/trips/' + trip['trip_id'] + '/actions'
        body = self.action(trip, 'offer_help')
        result = self.call('POST', path, body)
        self.assertEqual(self.call('POST', path, body), result)
        self.assertEqual(self.call('POST', path, {**body, 'action_id': 'allow_luggage'}, status=409)['error'], 'request_id_conflict')
        self.assertEqual(self.call('POST', path, {**body, 'request_id': uuid4().hex}, status=409)['error'], 'state_version_conflict')
        self.assertEqual(self.call('POST', '/api/trips/start', {'request_id': body['request_id']}, status=409)['error'], 'request_id_conflict')

    def test_concurrent_duplicate_and_competing_actions(self):
        trip = self.start()
        path = '/api/trips/' + trip['trip_id'] + '/actions'
        body = self.action(trip, 'offer_help')
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: request(self.url, 'POST', path, self.player, body), range(2)))
        self.assertEqual(results[0], results[1])
        trip = results[0][1]['trip']
        self.assertEqual(len(trip['history']), 1)
        bodies = [self.action(trip, 'place_free'), self.action(trip, 'allow_luggage')]
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda b: request(self.url, 'POST', path, self.player, b), bodies))
        self.assertEqual(sorted(r[0] for r in results), [200, 409])
        current = self.call('GET', '/api/trips/current')['trip']
        self.assertEqual(current['state_version'], 3)
        self.assertEqual(len(current['history']), 2)

    def test_process_restart_after_lost_response_and_report(self):
        start_body = {'request_id': 'stable-start'}
        started = self.call('POST', '/api/trips/start', start_body)
        trip = started['trip']
        path = '/api/trips/' + trip['trip_id']
        body = self.action(trip, 'allow_luggage')
        applied = self.call('POST', path + '/actions', body)
        report = self.call('GET', path + '/report')
        self.stop()
        self.launch()
        self.assertEqual(self.call('POST', path + '/actions', body), applied)
        self.assertEqual(self.call('POST', '/api/trips/start', start_body), started)
        self.assertEqual(self.call('GET', '/api/trips/current')['trip'], applied['trip'])
        self.assertEqual(self.call('GET', path + '/report'), report)
        self.assertEqual(len(report['report']['history']), 1)

    def test_current_attempt_new_attempt_and_completed(self):
        trip = self.start()
        path = '/api/trips/' + trip['trip_id']
        self.assertEqual(self.start()['trip_id'], trip['trip_id'])
        self.call('POST', '/api/trips/start', {'request_id': 'different-condition', 'luggage_space': 'occupied'}, status=409)
        self.call('POST', '/api/trips/start', {'request_id': 'retry', 'new_attempt': True}, status=409)
        self.call('GET', path + '/report', status=409)
        trip = self.call('POST', path + '/actions', self.action(trip, 'allow_luggage'))['trip']
        self.assertEqual(self.start()['status'], 'completed')
        self.call('POST', path + '/actions', self.action(trip, 'offer_help'), status=409)
        fresh = self.call('POST', '/api/trips/start', {'request_id': 'retry', 'new_attempt': True, 'luggage_space': 'occupied'})['trip']
        self.assertNotEqual(fresh['trip_id'], trip['trip_id'])
        self.assertEqual(self.call('GET', path + '/report')['report']['outcome'], 'allowed_blocked')

    def test_concurrent_start_creates_one_trip(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: request(self.url, 'POST', '/api/trips/start', self.player, {'request_id': uuid4().hex}), range(2)))
        self.assertEqual([r[0] for r in results], [200, 200])
        self.assertEqual(results[0][1]['trip_id'], results[1][1]['trip_id'])

    def test_input_validation(self):
        for body in [{'luggage_space': 'free'}, {'request_id': []}, {'request_id': 'x', 'luggage_space': []}, {'request_id': 'x', 'new_attempt': 1}, {'request_id': 'x', 'unexpected': 1}]:
            self.call('POST', '/api/trips/start', body, status=400)
        trip = self.start()
        for value in [True, 1.0, '1', None, -1]:
            self.call('POST', '/api/trips/' + trip['trip_id'] + '/actions', self.action(trip, 'offer_help', expected_state_version=value), status=400)
        self.call('GET', '/api/trips/start', status=405)
        self.call('GET', '/api/unknown-route', status=404)

    def test_malformed_json_and_nonfinite_numbers(self):
        from urllib.error import HTTPError
        for raw in [b'[]', b'{', b'{"request_id":"one","request_id":"two"}', b'{"request_id":"x","luggage_space":1e999}', b'{"request_id":"x","luggage_space":NaN}']:
            with self.subTest(raw=raw):
                with self.assertRaises(HTTPError) as context:
                    urlopen(Request(self.url + '/api/trips/start', raw, {'Content-Type': 'application/json', 'X-Demo-Player': self.player}))
                self.assertEqual(context.exception.code, 400)
                self.assertEqual(json.load(context.exception)['error'], 'invalid_json')
                context.exception.close()

    def test_active_restart_and_recovery_from_conflict(self):
        trip = self.start('occupied')
        path = '/api/trips/' + trip['trip_id']
        trip = self.call('POST', path + '/actions', self.action(trip, 'demand_removal'))['trip']
        self.stop()
        self.launch()
        self.assertEqual(self.call('GET', '/api/trips/current')['trip'], trip)
        for action_id in ['recover_help', 'check_alternative', 'place_alternative', 'finish_unchecked']:
            trip = self.call('POST', path + '/actions', self.action(trip, action_id))['trip']
        report = self.call('GET', path + '/report')['report']
        self.assertEqual(report['outcome'], 'not_verified')
        self.assertFalse(report['facts']['aisle_clear'])
        self.assertEqual(report['history'], trip['history'])
        self.assertEqual(len(report['history']), 5)

    def test_static_and_health(self):
        with urlopen(self.url + '/api/health') as r:
            self.assertTrue(json.load(r)['ok'])
        with urlopen(self.url + '/') as r:
            self.assertEqual(r.status, 200)
            self.assertIn(b'<html', r.read().lower())


class TransactionTests(unittest.TestCase):
    def test_rollback_when_request_record_fails_and_pinned_scenario(self):
        with tempfile.TemporaryDirectory() as directory:
            store = Store(Path(directory) / 'test.sqlite3')
            player = uuid4().hex
            start = store.mutate(player, '/api/trips/start', {'request_id': 'start'})
            trip = start['trip']
            with closing(sqlite3.connect(store.path)) as db, db:
                db.execute("CREATE TRIGGER fail_record BEFORE INSERT ON requests BEGIN SELECT RAISE(ABORT, 'simulated failure'); END")
            body = {'request_id': 'action', 'expected_state_version': 1, 'node_id': 'opening', 'incident_id': 'luggage-1', 'action_id': 'allow_luggage'}
            path = '/api/trips/' + trip['trip_id'] + '/actions'
            with self.assertRaises(sqlite3.IntegrityError):
                store.mutate(player, path, body, trip['trip_id'])
            self.assertEqual(store.get(player)['trip'], trip)
            with closing(sqlite3.connect(store.path)) as db, db:
                db.execute('DROP TRIGGER fail_record')
            store.scenario['nodes']['opening']['actions'][2]['effects']['safety_delta'] = -99
            result = store.mutate(player, path, body, trip['trip_id'])
            self.assertEqual(result['trip']['scales']['safety'], 80)
            self.assertEqual(Store(store.path).get(player)['trip'], result['trip'])


if __name__ == '__main__':
    unittest.main()
