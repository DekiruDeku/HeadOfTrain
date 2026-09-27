"""HUD clock commands affect the authoritative simulation and persist across reconnects."""
import tempfile
import unittest
from pathlib import Path
from uuid import uuid4
from backend.storage import Store, APIError
from backend.tests.test_b3 import Clock

class TimeControlTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.clock = Clock()
        self.db = Path(self.temp.name) / 'clock.sqlite3'
        self.store = Store(self.db, clock_ms=self.clock)
        self.player = uuid4().hex
        self.trip = self.store.mutate(self.player, '/api/trips/start', {
            'request_id': uuid4().hex, 'simulation_mode': 'full_b4'})['trip']

    def get(self, seconds=0):
        self.clock.step(seconds)
        self.trip = self.store.get(self.player)['trip']
        return self.trip

    def command(self, operation, **fields):
        path = '/api/trips/' + self.trip['trip_id'] + '/' + operation
        body = dict(request_id=uuid4().hex, expected_state_version=self.trip['state_version'], **fields)
        result = self.store.mutate(self.player, path, body, self.trip['trip_id'])
        self.trip = result['trip']
        return path, body, result

    def test_pause_freezes_route_reaction_and_trip_then_resumes(self):
        self.command('assignments', incident_id='blanket-1', staff_id='staff-1')
        self.get(1)
        self.command('time', speed=0)
        before = self.trip
        self.get(25)
        self.assertEqual(self.trip['simulation_time'], before['simulation_time'])
        self.assertEqual(self.trip['staff'], before['staff'])
        self.assertEqual(self.trip['incidents'], before['incidents'])
        self.assertTrue(self.trip['paused'])
        self.assertEqual(self.trip['pause_reason'], 'user')
        self.command('time', speed=1)
        self.get(1)
        self.assertEqual(self.trip['simulation_time'], before['simulation_time']+1)
        self.assertFalse(self.trip['paused'])

    def test_speed_changes_and_arrival_service_boundaries(self):
        self.command('assignments', incident_id='blanket-1', staff_id='staff-1')
        self.command('time', speed=2)
        self.get(2)
        self.assertEqual(self.trip['simulation_time'], 4)
        self.assertEqual(next(i for i in self.trip['incidents'] if i['id']=='blanket-1')['state'], 'resolving')
        self.command('time', speed=4)
        self.get(5)
        self.assertEqual(self.trip['simulation_time'], 24)
        self.assertEqual(next(i for i in self.trip['incidents'] if i['id']=='blanket-1')['resolution'], 'served')

    def test_pause_persists_and_replay_does_not_reapply(self):
        path, body, response = self.command('time', speed=0)
        self.store = Store(self.db, clock_ms=self.clock)
        self.get(60)
        self.assertEqual(self.trip['simulation_time'], 0)
        self.command('time', speed=2)
        replay = self.store.mutate(self.player, path, body, self.trip['trip_id'])
        self.assertEqual(replay, response)
        self.get(1)
        self.assertEqual(self.trip['time_speed'], 2)
        self.assertEqual(self.trip['simulation_time'], 2)

    def test_invalid_speeds_and_stale_version(self):
        for speed in [-1, 3, 8, True, '2', None]:
            with self.subTest(speed=speed), self.assertRaises(APIError) as raised:
                self.command('time', speed=speed)
            self.assertEqual(raised.exception.status, 422)
        path, body, _ = self.command('time', speed=2)
        body['request_id'] = uuid4().hex
        with self.assertRaises(APIError) as raised:
            self.store.mutate(self.player, path, body, self.trip['trip_id'])
        self.assertEqual(raised.exception.data['error'], 'state_version_conflict')

    def test_dialog_decision_clock_remains_real_time(self):
        self.command('time', speed=4)
        self.command('assignments', incident_id='luggage-1', staff_id='staff-3')
        self.command('dialog/open', incident_id='luggage-1')
        before = self.trip['dialog']['critical_decision_time']
        self.get(2)
        self.assertEqual(self.trip['simulation_time'], 0)
        self.assertEqual(self.trip['dialog']['critical_decision_time'], before-2)
        with self.assertRaises(APIError) as raised:
            self.command('time', speed=0)
        self.assertEqual(raised.exception.data['error'], 'dialog_open')

    def test_completion_at_fast_speed_is_immutable(self):
        self.command('time', speed=4)
        self.get(100)
        self.assertEqual(self.trip['status'], 'completed')
        self.assertEqual(self.trip['simulation_time'], 360)
        with self.assertRaises(APIError):
            self.command('time', speed=1)

    def test_same_point_assignment_during_pause_arrives_immediately(self):
        self.command('time', speed=0)
        self.command('assignments', incident_id='luggage-1', staff_id='staff-3')
        self.assertEqual(self.trip['staff'][2]['state'], 'serving')
        self.assertEqual(self.trip['incidents'][0]['state'], 'resolving')
        self.assertEqual(self.trip['simulation_time'], 0)
        self.command('dialog/open', incident_id='luggage-1')
        self.command('dialog/close', incident_id='luggage-1')
        self.assertTrue(self.trip['paused'])
        self.assertEqual(self.trip['pause_reason'], 'user')

    def test_dialog_timeout_restores_manual_pause_for_remaining_wall_time(self):
        self.command('time', speed=0)
        self.command('assignments', incident_id='luggage-1', staff_id='staff-3')
        self.command('dialog/open', incident_id='luggage-1')
        deadline = self.trip['dialog']['critical_decision_time']
        self.get(deadline+5)
        self.assertEqual(self.trip['simulation_time'], 0)
        self.assertEqual(self.trip['pause_reason'], 'user')

    def test_dialog_timeout_restores_acceleration_for_remaining_wall_time(self):
        self.command('time', speed=4)
        self.command('assignments', incident_id='luggage-1', staff_id='staff-3')
        self.command('dialog/open', incident_id='luggage-1')
        deadline = self.trip['dialog']['critical_decision_time']
        self.get(deadline+2)
        self.assertEqual(self.trip['simulation_time'], 8)
