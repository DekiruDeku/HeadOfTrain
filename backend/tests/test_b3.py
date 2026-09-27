"""B3 boundaries use an injected SERVER clock; production API never accepts time."""
import json
import sqlite3
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from copy import deepcopy
from pathlib import Path
from uuid import uuid4

from backend.storage import Store, APIError


class Clock:
    def __init__(self):
        self.ms = 1800000000000

    def __call__(self):
        return self.ms

    def step(self, seconds):
        self.ms += round(seconds * 1000)


class SimulationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.clock = Clock()
        self.path = Path(self.temp.name) / 'b3.sqlite3'
        self.store = Store(self.path, clock_ms=self.clock)
        self.player = uuid4().hex
        self.trip = self.start()

    def start(self, **extra):
        return self.store.mutate(self.player, '/api/trips/start', {
            'request_id': uuid4().hex, 'simulation_mode': 'crew_b3', **extra})['trip']

    def get(self, seconds=0):
        self.clock.step(seconds)
        self.trip = self.store.get(self.player)['trip']
        return self.trip

    def body(self, **extra):
        return {'request_id': uuid4().hex, 'expected_state_version': self.trip['state_version'],
                'incident_id': 'luggage-1', **extra}

    def post(self, endpoint, body):
        result = self.store.mutate(self.player, '/api/trips/' + self.trip['trip_id'] + '/' + endpoint, body, self.trip['trip_id'])
        self.trip = result['trip']
        return result

    def assign(self, staff='staff-3', incident='luggage-1'):
        return self.post('assignments', self.body(staff_id=staff, incident_id=incident))

    def dialog(self, endpoint='open'):
        return self.post('dialog/' + endpoint, self.body())

    def act(self, action):
        return self.post('actions', self.body(node_id=self.trip['node_id'], action_id=action))

    def item(self, id='luggage-1'):
        return next(i for i in self.trip['incidents'] if i['id'] == id)

    def staff(self, id='staff-3'):
        return next(s for s in self.trip['staff'] if s['id'] == id)

    def error(self, code, endpoint, body):
        with self.assertRaises(APIError) as raised:
            self.post(endpoint, body)
        self.assertEqual(raised.exception.data['error'], code)
        return raised.exception

    def test_initial_two_carriages_three_staff_two_services(self):
        self.assertEqual(len(self.trip['carriages']), 2)
        self.assertEqual(len(self.trip['staff']), 3)
        self.assertEqual(len(self.trip['incidents']), 3)
        self.assertEqual(len(self.trip['assignment_options']), 9)
        self.assertIsNone(self.trip['dialog'])
        self.assertIsNone(self.trip['scales']['overall_loyalty'])
        self.assertFalse(any(k.startswith('_') for k in self.trip))

    def test_estimates_route_position_and_reaction_keeps_running(self):
        self.assign('staff-1')
        self.assertEqual(self.staff('staff-1')['arrival_remaining'], 18)
        self.assertEqual(self.staff('staff-1')['route']['point_ids'], ['c1-desk', 'c1-blanket', 'c1-door', 'c2-door', 'c2-luggage'])
        self.get(10)
        self.assertEqual(self.item()['reaction_time'], 50)
        self.assertEqual(self.staff('staff-1')['route_point_id'], 'c1-door')
        self.assertEqual(self.staff('staff-1')['position'], {'from': 'c1-door', 'to': 'c2-door', 'progress': 2/6})
        self.get(4)
        self.assertEqual(self.staff('staff-1')['carriage_id'], 'carriage-2')
        self.get(4)
        self.assertIsNone(self.item()['reaction_time'])
        self.assertEqual(self.item()['arrived_at'], 18)
        self.assertEqual(self.staff('staff-1')['state'], 'serving')
        self.assertEqual(self.trip['dialog']['critical_decision_time'], 30)

    def test_same_point_immediate_arrival(self):
        self.assign()
        self.assertEqual(self.trip['state_version'], 3)
        self.assertEqual(self.item()['state'], 'resolving')
        self.assertEqual(self.item()['arrived_at'], 0)
        self.assertIsNone(self.item()['reaction_time'])

    def test_busy_moving_and_serving_rejected(self):
        self.assign('staff-1', 'blanket-1')
        self.error('staff_busy', 'assignments', self.body(staff_id='staff-1'))
        self.get(4)
        self.error('staff_busy', 'assignments', self.body(staff_id='staff-1'))
        self.assertEqual(self.staff('staff-1')['state'], 'serving')

    def test_two_services_finish_exactly_and_employee_stays(self):
        self.assign('staff-1', 'blanket-1')
        self.assign('staff-2', 'table-1')
        self.get(18.999)
        self.assertEqual(self.item('table-1')['service_remaining'], .001)
        self.get(.001)
        self.assertEqual(self.item('table-1')['resolution'], 'served')
        self.assertEqual(self.staff('staff-2')['route_point_id'], 'c2-table')
        self.assertEqual(self.staff('staff-2')['state'], 'free')
        self.assertEqual(self.trip['scales']['overall_loyalty'], 56)
        self.get(5)
        self.assertEqual(self.staff('staff-1')['route_point_id'], 'c1-blanket')
        self.assertEqual(self.staff('staff-1')['carriage_id'], 'carriage-1')
        self.assertEqual(self.trip['scales']['overall_loyalty'], 57)
        self.assertEqual(self.trip['scales']['safety'], 100)
        self.assertEqual(len(self.trip['history']), 2)
        self.get(1)
        self.assertEqual(len(self.trip['history']), 2)
        self.assign('staff-2')
        self.assertEqual(self.staff('staff-2')['arrival_remaining'], 5)

    def test_open_requires_arrival_and_action_requires_open(self):
        self.error('dialog_not_ready', 'dialog/open', self.body())
        self.assign()
        self.error('dialog_not_open', 'actions', self.body(node_id='opening', action_id='allow_luggage'))
        self.dialog()
        self.assertTrue(self.trip['paused'])
        self.act('allow_luggage')
        self.assertFalse(self.trip['paused'])
        self.assertIsNone(self.trip['dialog'])

    def test_pause_freezes_movement_service_and_other_reaction(self):
        self.assign('staff-1', 'blanket-1')
        self.get(4)
        self.assign('staff-2', 'table-1')
        self.assign()
        self.dialog()
        before = deepcopy(self.trip)
        self.get(10)
        self.assertEqual(self.trip['simulation_time'], 4)
        self.assertEqual(self.trip['staff'], before['staff'])
        self.assertEqual(self.trip['incidents'], before['incidents'])
        self.assertEqual(self.trip['dialog']['critical_decision_time'], 20)
        self.error('simulation_paused', 'assignments', self.body(staff_id='staff-1'))
        self.dialog('close')
        self.get(4)
        self.assertEqual(self.trip['simulation_time'], 8)
        self.assertEqual(self.item('table-1')['state'], 'resolving')
        self.assertEqual(self.item('blanket-1')['service_remaining'], 16)

    def test_closed_dialog_critical_clock_continues_no_reset_on_open(self):
        self.assign()
        self.get(3)
        self.dialog()
        self.get(5)
        self.dialog()
        self.assertEqual(self.trip['dialog']['critical_decision_time'], 22)
        self.dialog('close')
        self.get(4)
        self.dialog('close')
        self.dialog()
        self.assertEqual(self.trip['dialog']['critical_decision_time'], 18)
        self.assertEqual(self.trip['simulation_time'], 7)

    def test_noncritical_dialog_freezes_indefinitely_then_verify_gets_new_clock(self):
        self.assign()
        self.dialog()
        self.act('offer_help')
        self.assertIsNone(self.trip['dialog']['critical_decision_time'])
        self.get(1000)
        self.assertEqual(self.trip['simulation_time'], 0)
        self.assertEqual(self.item('blanket-1')['reaction_time'], 90)
        self.act('place_free')
        self.assertEqual(self.trip['dialog']['critical_decision_time'], 20)
        self.get(19.999)
        self.assertEqual(self.trip['dialog']['critical_decision_time'], .001)
        self.act('confirm_clear')
        self.assertEqual(self.item()['resolution'], 'resolved')
        self.assertFalse(self.trip['paused'])

    def test_critical_deadline_exactly_wins_over_player_and_is_committed(self):
        self.assign()
        self.dialog()
        stale = self.body(node_id='opening', action_id='allow_luggage')
        self.clock.step(30)
        self.error('state_version_conflict', 'actions', stale)
        # Read raw DB first: an error must not roll back elapsed automatic effects.
        with closing(self.store.connect()) as db:
            state = json.loads(db.execute('SELECT state_json FROM trips').fetchone()[0])
            self.assertEqual(state['outcome'], 'decision_timeout')
            self.assertEqual(len(state['history']), 1)
        self.get()
        self.assertEqual(self.trip['critical_marks'], ['aisle_decision_missed'])
        self.assertEqual(self.trip['scales']['safety'], 85)
        self.assertEqual(self.trip['history'][0]['decision_time_seconds'], 30)
        self.assertEqual(self.trip['simulation_time'], 0)
        self.assertFalse(self.trip['paused'])
        self.get(10)
        self.assertEqual(len(self.trip['history']), 1)

    def test_critical_timeout_unpauses_at_boundary_during_long_gap(self):
        self.assign('staff-1', 'blanket-1')
        self.assign()
        self.dialog()
        self.get(55)
        self.assertEqual(self.trip['simulation_time'], 25)
        self.assertEqual(self.item('blanket-1')['resolution'], 'served')
        self.assertEqual(self.item('table-1')['reaction_time'], 75)
        self.assertEqual(self.trip['history'][0]['source'], 'decision_timeout')
        self.assertEqual(self.trip['history'][1]['simulation_time'], 24)

    def test_reaction_timeout_one_millisecond_boundary(self):
        self.get(59.999)
        self.assertEqual(self.item()['reaction_time'], .001)
        self.get(.001)
        self.assertEqual(self.item()['resolution'], 'response_timeout')
        self.get(40)
        self.assertEqual(self.trip['status'], 'completed')
        self.assertEqual(len(self.trip['history']), 3)
        self.assertEqual(self.trip['scales']['overall_loyalty'], 42)
        self.assertEqual(self.trip['scales']['safety'], 85)
        old = deepcopy(self.trip)
        self.assertEqual(self.get(100000), old)

    def test_arrival_on_reaction_deadline_loses(self):
        self.get(42)
        self.assign('staff-1')
        self.get(18)
        self.assertEqual(self.item()['resolution'], 'response_timeout')
        self.assertEqual(self.staff('staff-1')['state'], 'free')
        self.assertEqual(self.staff('staff-1')['route_point_id'], 'c2-luggage')

    def test_arrival_just_before_deadline_succeeds(self):
        self.get(41.999)
        self.assign('staff-1')
        self.get(18)
        self.assertEqual(self.item()['state'], 'resolving')
        self.assertEqual(self.trip['history'], [])

    def test_late_employee_continues_route_without_teleport_or_service(self):
        self.get(55)
        self.assign('staff-1')
        self.get(5)
        self.assertEqual(self.item()['resolution'], 'response_timeout')
        self.assertEqual(self.staff('staff-1')['state'], 'moving')
        self.assertEqual(self.staff('staff-1')['route_point_id'], 'c1-blanket')
        self.get(13)
        self.assertEqual(self.staff('staff-1')['state'], 'free')
        self.assertEqual(self.staff('staff-1')['route_point_id'], 'c2-luggage')
        self.assertEqual(len(self.trip['history']), 1)

    def test_critical_mark_not_compensated_by_positive_service(self):
        self.assign('staff-1', 'blanket-1')
        self.assign('staff-2', 'table-1')
        self.assign()
        self.dialog()
        self.act('allow_luggage')
        self.assertEqual(self.trip['scales']['overall_loyalty'], 54)
        self.get(24)
        self.assertEqual(self.trip['status'], 'completed')
        self.assertEqual(self.trip['scales']['overall_loyalty'], 56)
        self.assertEqual(self.trip['scales']['safety'], 80)
        self.assertEqual(self.trip['critical_marks'], ['aisle_left_blocked'])
        report = self.store.get(self.player, report=True)['report']
        self.assertEqual(report['history'], self.trip['history'])
        self.assertEqual(report['critical_marks'], self.trip['critical_marks'])
        self.assertEqual(report['scales'], self.trip['scales'])

    def test_overall_counts_unique_participants_only_completed_incidents(self):
        # Same passenger in two situations must not be weighted twice.
        other = uuid4().hex
        self.store.simulation_config['incidents'][2]['participant_ids'] = ['blanket-passenger', 'table-passenger']
        self.player = other
        self.trip = self.start()
        self.assign('staff-1', 'blanket-1')
        self.assign('staff-2', 'table-1')
        self.get(24)
        self.assertEqual(self.trip['completed_participant_ids'], ['blanket-passenger', 'table-passenger'])
        self.assertEqual(self.trip['scales']['overall_loyalty'], 60)
        self.assertEqual(self.trip['scales']['loyalty']['luggage-owner'], 50)

    def test_assignment_replay_and_changed_body(self):
        body = self.body(staff_id='staff-1', incident_id='blanket-1')
        original = self.post('assignments', body)
        self.get(24)
        self.assertEqual(self.post('assignments', body), original)
        self.error('request_id_conflict', 'assignments', {**body, 'staff_id': 'staff-2'})
        self.get()
        self.assertEqual(len(self.trip['history']), 1)
        self.assertEqual(self.trip['scales']['loyalty']['blanket-passenger'], 58)

    def test_action_and_dialog_replays_do_not_repeat_effect_or_pause(self):
        self.assign()
        body = self.body()
        opened = self.post('dialog/open', body)
        choice = self.body(node_id='opening', action_id='allow_luggage')
        result = self.post('actions', choice)
        self.get(7)
        self.assertEqual(self.post('dialog/open', body), opened)
        self.assertEqual(self.post('actions', choice), result)
        self.get()
        self.assertFalse(self.trip['paused'])
        self.assertEqual(self.trip['scales']['safety'], 80)
        self.assertEqual(len(self.trip['history']), 1)

    def race(self, endpoint, bodies):
        trip_id = self.trip['trip_id']
        path = '/api/trips/' + trip_id + '/' + endpoint
        barrier = threading.Barrier(2)
        def run(body):
            barrier.wait(timeout=5)
            try:
                return (200, self.store.mutate(self.player, path, body, trip_id))
            except APIError as e:
                return e.status, e.data
        with ThreadPoolExecutor(max_workers=2) as pool:
            return list(pool.map(run, bodies))

    def test_concurrent_assignments_same_employee(self):
        results = self.race('assignments', [self.body(staff_id='staff-1', incident_id=i) for i in ('blanket-1', 'table-1')])
        self.assertEqual(sorted(x[0] for x in results), [200, 409])
        self.get()
        self.assertEqual(sum(i['state'] == 'en_route' for i in self.trip['incidents']), 1)

    def test_concurrent_assignments_same_incident(self):
        results = self.race('assignments', [self.body(staff_id=s) for s in ('staff-1', 'staff-2')])
        self.assertEqual(sorted(x[0] for x in results), [200, 409])
        self.get()
        self.assertEqual(sum(s['state'] == 'moving' for s in self.trip['staff']), 1)

    def test_concurrent_duplicate_assignment_exact_response(self):
        body = self.body(staff_id='staff-1')
        results = self.race('assignments', [body, body])
        self.assertEqual(results[0], results[1])
        self.get()
        self.assertEqual(len(self.trip['events']), 1)

    def test_concurrent_get_timeout_only_once(self):
        self.clock.step(100)
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: self.store.get(self.player), range(4)))
        self.assertTrue(all(r == results[0] for r in results))
        self.assertEqual(len(results[0]['trip']['history']), 3)

    def test_restart_from_movement_service_and_paused_dialog(self):
        self.assign('staff-1', 'blanket-1')
        self.get(2)
        self.store = Store(self.path, clock_ms=self.clock)
        self.get(3)
        self.assertEqual(self.item('blanket-1')['service_remaining'], 19)
        self.assign()
        self.dialog()
        self.clock.step(10)
        self.store = Store(self.path, clock_ms=self.clock)
        self.get()
        self.assertEqual(self.trip['dialog']['critical_decision_time'], 20)
        self.assertEqual(self.item('blanket-1')['service_remaining'], 19)
        self.assertEqual(self.trip['simulation_time'], 5)
        self.get(21)
        self.assertEqual(self.trip['simulation_time'], 6)
        self.assertEqual(self.item('blanket-1')['service_remaining'], 18)

    def test_clock_rollback_does_not_add_or_repeat_time(self):
        self.get(10)
        old = deepcopy(self.trip)
        self.assertEqual(self.get(-5), old)
        self.assertEqual(self.get(5), old)
        self.get(1)
        self.assertEqual(self.trip['simulation_time'], 11)

    def test_poll_frequency_independent(self):
        self.assign('staff-1', 'blanket-1')
        self.assign('staff-2', 'table-1')
        self.assign()
        self.dialog()
        # Copy SQLite using its backup API, including committed WAL.
        second_path = Path(self.temp.name) / 'copy.sqlite3'
        with closing(self.store.connect()) as src, closing(sqlite3.connect(second_path)) as dst:
            src.backup(dst)
        second_clock = Clock()
        second = Store(second_path, clock_ms=second_clock)
        self.get(200)
        for _ in range(400):
            second_clock.step(.5)
            actual = second.get(self.player)['trip']
        self.assertEqual(self.trip, actual)

    def test_simulation_config_and_scenario_pinned_after_restart(self):
        self.assign('staff-1', 'blanket-1')
        self.store.simulation_config['incidents'][1]['success']['loyalty_delta'] = 999
        self.store.simulation_config['edge_seconds'][0] = 999
        self.store.simulation_config['critical_nodes']['opening']['seconds'] = 999
        self.store.scenario['nodes']['opening']['actions'][2]['effects']['safety_delta'] = -99
        self.assign()
        self.dialog()
        self.assertEqual(self.trip['dialog']['critical_decision_time'], 30)
        self.act('allow_luggage')
        self.get(24)
        self.assertEqual(self.trip['scales']['safety'], 80)
        self.assertEqual(self.trip['scales']['loyalty']['blanket-passenger'], 58)
        self.store = Store(self.path, clock_ms=self.clock)
        self.get()
        self.assertEqual(self.trip['scales']['loyalty']['blanket-passenger'], 58)

    def test_storage_failure_rolls_back_clock_command_and_dedup(self):
        self.assign('staff-1', 'blanket-1')
        self.clock.step(24)
        body = self.body(staff_id='staff-2', incident_id='table-1')
        # Use expected version after due arrival and service.
        body['expected_state_version'] += 2
        with closing(self.store.connect()) as db:
            db.execute("CREATE TRIGGER fail_record BEFORE INSERT ON requests BEGIN SELECT RAISE(ABORT, 'test'); END")
        with self.assertRaises(sqlite3.IntegrityError):
            self.post('assignments', body)
        with closing(self.store.connect()) as db:
            stored = json.loads(db.execute('SELECT state_json FROM trips').fetchone()[0])
            self.assertEqual(stored['_sim_ms'], 0)
            self.assertEqual(stored['history'], [])
            db.execute('DROP TRIGGER fail_record')
        self.post('assignments', body)
        self.assertEqual(len(self.trip['history']), 1)
        self.assertEqual(self.staff('staff-2')['state'], 'moving')

    def test_bad_inputs_ownership_and_no_client_time(self):
        for staff in ('other',):
            self.error('invalid_staff', 'assignments', self.body(staff_id=staff))
        self.error('invalid_incident', 'assignments', self.body(staff_id='staff-1', incident_id='unknown'))
        self.error('invalid_fields', 'assignments', self.body(staff_id='staff-1', elapsed=50))
        self.error('invalid_fields', 'dialog/open', self.body(safety=100))
        for version in (True, 1.0, '1', None, -1):
            self.error('invalid_state_version', 'assignments', self.body(staff_id='staff-1', expected_state_version=version))
        with self.assertRaises(APIError) as e:
            self.store.mutate(uuid4().hex, '/api/trips/'+self.trip['trip_id']+'/assignments', self.body(staff_id='staff-1'), self.trip['trip_id'])
        self.assertEqual(e.exception.status, 404)
        self.assertEqual(self.get()['state_version'], 1)

    def test_assigned_incident_and_service_dialog_rejected(self):
        self.assign('staff-1', 'blanket-1')
        self.error('incident_unavailable', 'assignments', self.body(staff_id='staff-2', incident_id='blanket-1'))
        self.get(4)
        self.error('dialog_not_ready', 'dialog/open', self.body(incident_id='blanket-1'))

    def test_mode_resume_and_new_attempt(self):
        restored = self.store.mutate(self.player, '/api/trips/start', {'request_id': uuid4().hex})
        self.assertEqual(restored['trip'], self.trip)
        with self.assertRaises(APIError) as e:
            self.start(simulation_mode='untimed_b1')
        self.assertEqual(e.exception.data['error'], 'mode_conflict')
        old_id = self.trip['trip_id']
        self.clock.step(100)
        fresh = self.start(new_attempt=True)
        self.assertNotEqual(fresh['trip_id'], old_id)
        self.assertEqual(self.store.get(self.player, old_id, report=True)['report']['outcome'], 'response_timeout')

    def test_report_get_catches_up_and_final_snapshot_immutable(self):
        self.clock.step(1000)
        report = self.store.get(self.player, report=True)['report']
        self.assertEqual(len(report['history']), 3)
        self.assertEqual(report['scales']['safety'], 85)
        self.store = Store(self.path, clock_ms=self.clock)
        self.clock.step(1000)
        self.assertEqual(self.store.get(self.player, report=True)['report'], report)

    def test_verify_timeout_only_once_and_no_score_for_unconfirmed_result(self):
        self.assign()
        self.dialog()
        self.act('offer_help')
        self.act('place_free')
        self.get(20)
        self.assertEqual(self.trip['outcome'], 'decision_timeout')
        self.assertEqual(self.trip['scales']['loyalty']['luggage-owner'], 45)
        self.assertFalse(self.trip['facts']['aisle_clear'])
        self.assertEqual(len(self.trip['history']), 3)
        self.get(1)
        self.assertEqual(len(self.trip['history']), 3)


if __name__ == '__main__':
    unittest.main()
