"""Real HTTP, process death and missing responses for the B3 simulation."""
import json
import sqlite3
from contextlib import closing
import subprocess
import sys
from pathlib import Path
from uuid import uuid4

from backend.tests.test_b2 import ServerCase, ROOT


class B3HTTPTests(ServerCase):
    def launch(self, gated=False):
        clock = Path(self.temp.name) / 'clock.txt'
        if not clock.exists():
            clock.write_text('1800000000000')
        self.clock_file = clock
        self.process = subprocess.Popen([sys.executable, '-u', str(ROOT / 'backend/tests/clock_server.py'),
                                        '--db', str(self.db), '--clock-file', str(clock)],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.log, bufsize=0)
        line = self.control_line()
        self.assertTrue(line.startswith('Game: '), line)
        self.url = line.removeprefix('Game: ').rstrip('/')

    def tick(self, seconds):
        # Atomic file swap; only the test process controls the server clock.
        temp = self.clock_file.with_suffix('.next')
        temp.write_text(str(int(self.clock_file.read_text()) + round(seconds * 1000)))
        temp.replace(self.clock_file)

    def crew(self):
        return self.start(simulation_mode='crew_b3')

    def command(self, trip, endpoint, **fields):
        body = {'request_id': uuid4().hex, 'expected_state_version': trip['state_version'], 'incident_id': 'luggage-1', **fields}
        return self.call('POST', '/api/trips/' + trip['trip_id'] + '/' + endpoint, body)['trip']

    def get_trip(self):
        return self.call('GET', '/api/trips/current')['trip']

    def test_http_restart_movement_service_and_final_report(self):
        trip = self.crew()
        trip = self.command(trip, 'assignments', staff_id='staff-1', incident_id='blanket-1')
        self.stop(hard=True)
        self.tick(5)
        self.launch()
        trip = self.get_trip()
        self.assertEqual(trip['incidents'][1]['service_remaining'], 19)
        self.stop(hard=True)
        self.tick(19)
        self.launch()
        trip = self.get_trip()
        self.assertEqual(trip['incidents'][1]['resolution'], 'served')
        self.assertEqual(trip['staff'][0]['route_point_id'], 'c1-blanket')
        self.tick(76)
        report = self.call('GET', '/api/trips/' + trip['trip_id'] + '/report')['report']
        self.assertEqual(len(report['history']), 3)
        self.stop(hard=True)
        self.tick(1000)
        self.launch()
        self.assertEqual(self.call('GET', '/api/trips/' + trip['trip_id'] + '/report')['report'], report)

    def test_http_pause_restart_and_timeout_catchup(self):
        trip = self.crew()
        trip = self.command(trip, 'assignments', staff_id='staff-1', incident_id='blanket-1')
        trip = self.command(trip, 'assignments', staff_id='staff-3')
        trip = self.command(trip, 'dialog/open')
        self.stop(hard=True)
        self.tick(20)
        self.launch()
        trip = self.get_trip()
        self.assertTrue(trip['paused'])
        self.assertEqual(trip['simulation_time'], 0)
        self.assertEqual(trip['dialog']['critical_decision_time'], 10)
        self.stop(hard=True)
        self.tick(35)
        self.launch()
        trip = self.get_trip()
        self.assertFalse(trip['paused'])
        self.assertEqual(trip['simulation_time'], 25)
        self.assertEqual(trip['incidents'][1]['resolution'], 'served')
        self.assertEqual(trip['scales']['safety'], 85)

    def test_lost_assignment_response_replay_after_process_death(self):
        trip = self.crew()
        path = '/api/trips/' + trip['trip_id'] + '/assignments'
        body = dict(request_id='assignment-lost', expected_state_version=1, incident_id='blanket-1', staff_id='staff-1')
        sock = self.held_request(path, body)
        stored = self.saved()
        response = json.loads(next(r[3] for r in stored['requests'] if r[1] == body['request_id']))
        self.stop(hard=True)
        self.assert_disconnected(sock)
        self.tick(24)
        self.launch()
        self.assertEqual(self.call('POST', path, body), response)
        current = self.get_trip()
        self.assertEqual(current['scales']['loyalty']['blanket-passenger'], 58)
        self.assertEqual(len(current['history']), 1)
        self.assertEqual(self.call('POST', path, body), response)
        self.assertEqual(self.get_trip(), current)

    def test_lost_open_response_does_not_restart_timer_or_pause(self):
        trip = self.crew()
        trip = self.command(trip, 'assignments', staff_id='staff-3')
        path = '/api/trips/' + trip['trip_id'] + '/dialog/open'
        body = dict(request_id='open-lost', expected_state_version=trip['state_version'], incident_id='luggage-1')
        sock = self.held_request(path, body)
        self.stop(hard=True)
        self.assert_disconnected(sock)
        self.tick(35)
        self.launch()
        replay = self.call('POST', path, body)
        self.assertTrue(replay['trip']['paused'])
        current = self.get_trip()
        self.assertFalse(current['paused'])
        self.assertEqual(current['simulation_time'], 5)
        self.assertEqual(current['outcome'], 'decision_timeout')
        self.assertEqual(self.call('POST', path, body), replay)
        self.assertEqual(self.get_trip(), current)

    def test_crash_before_commit_rolls_back_assignment_and_repeat_succeeds(self):
        trip = self.crew()
        path = '/api/trips/' + trip['trip_id'] + '/assignments'
        body = dict(request_id='hold-before-commit', expected_state_version=1, incident_id='blanket-1', staff_id='staff-1')
        sock = self.held_request(path, body, expected='UNCOMMITTED')
        self.stop(hard=True)
        self.assert_disconnected(sock)
        self.launch()
        self.assertEqual(self.get_trip(), trip)
        # The gate waits only on this ID; release it on retry.
        self.process.stdin.write(b'release\nrelease\n')
        self.process.stdin.flush()
        result = self.call('POST', path, body)
        self.assertEqual(self.control_line(), 'UNCOMMITTED')
        self.assertEqual(len(result['trip']['events']), 1)
        self.assertEqual(self.call('POST', path, body), result)

    def test_http_deadline_error_commits_once_and_rejects_client_time(self):
        trip = self.crew()
        path = '/api/trips/' + trip['trip_id']
        body = dict(request_id='late', expected_state_version=1, incident_id='luggage-1', staff_id='staff-3')
        self.tick(60)
        self.assertEqual(self.call('POST', path + '/assignments', body, status=409)['error'], 'state_version_conflict')
        with closing(sqlite3.connect(self.db)) as db, db:
            state = json.loads(db.execute('SELECT state_json FROM trips').fetchone()[0])
        self.assertEqual(len(state['history']), 1)
        self.call('POST', path + '/assignments', {**body, 'elapsed': 0}, status=400)
        self.assertEqual(len(self.get_trip()['history']), 1)
        for suffix in ('assignments', 'dialog/open', 'dialog/close'):
            self.call('GET', path + '/' + suffix, status=405)
            self.call('POST', path + '/' + suffix, body, player=uuid4().hex, status=404)

    def test_full_b3_help_path_over_http_and_close(self):
        trip = self.crew()
        trip = self.command(trip, 'assignments', staff_id='staff-1', incident_id='blanket-1')
        trip = self.command(trip, 'assignments', staff_id='staff-2', incident_id='table-1')
        trip = self.command(trip, 'assignments', staff_id='staff-3')
        trip = self.command(trip, 'dialog/open')
        self.tick(3)
        trip = self.command(self.get_trip(), 'dialog/close')
        self.assertFalse(trip['paused'])
        self.tick(2)
        trip = self.command(self.get_trip(), 'dialog/open')
        for action in ('offer_help', 'place_free', 'confirm_clear'):
            trip = self.act(trip, action)
        self.tick(22)
        trip = self.get_trip()
        self.assertEqual(trip['status'], 'completed')
        self.assertEqual(trip['scales']['loyalty'], {'luggage-owner': 58, 'blanket-passenger': 58, 'table-passenger': 56})
        self.assertEqual(trip['scales']['safety'], 100)
        self.assertEqual(trip['critical_marks'], [])
        self.assertTrue(trip['facts']['aisle_clear'])

    def test_lost_critical_action_response_preserves_effect_once(self):
        trip = self.crew()
        trip = self.command(trip, 'assignments', staff_id='staff-1', incident_id='blanket-1')
        trip = self.command(trip, 'assignments', staff_id='staff-2', incident_id='table-1')
        trip = self.command(trip, 'assignments', staff_id='staff-3')
        trip = self.command(trip, 'dialog/open')
        path = '/api/trips/' + trip['trip_id'] + '/actions'
        body = {**self.body(trip, 'allow_luggage'), 'request_id': 'allow-lost'}
        sock = self.held_request(path, body)
        self.stop(hard=True)
        self.assert_disconnected(sock)
        self.tick(24)
        self.launch()
        reply = self.call('POST', path, body)
        self.assertEqual(reply['trip']['scales']['safety'], 80)
        current = self.get_trip()
        self.assertEqual(current['status'], 'completed')
        self.assertEqual(len(current['history']), 3)
        self.assertEqual(current['scales']['overall_loyalty'], 56)
        self.assertEqual(current['critical_marks'], ['aisle_left_blocked'])
        self.assertEqual(self.call('POST', path, body), reply)
        self.assertEqual(self.get_trip(), current)
