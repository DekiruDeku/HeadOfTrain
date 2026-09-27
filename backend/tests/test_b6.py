"""Final full-trip races, real HTTP recovery and non-destructive SQLite snapshots."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
from uuid import uuid4

from backend.database import snapshot
from backend.demo import request
from backend.storage import Store
from backend.tests import test_b3_http, test_b4
from backend.tests.test_b2 import ServerCase


class B6HTTPTests(ServerCase):
    launch = test_b3_http.B3HTTPTests.launch
    tick = test_b3_http.B3HTTPTests.tick

    def race(self, path, bodies):
        barrier = threading.Barrier(len(bodies))
        def send(body):
            barrier.wait(timeout=10)
            return request(self.url, 'POST', path, self.player, body)
        with ThreadPoolExecutor(max_workers=len(bodies)) as pool:
            return list(pool.map(send, bodies))

    def test_full_trip_concurrent_start_assignment_and_choices(self):
        replies = self.race('/api/trips/start', [dict(request_id=uuid4().hex, simulation_mode='full_b4') for _ in range(8)])
        self.assertTrue(all(code == 200 for code, _ in replies))
        self.assertEqual(len({data['trip_id'] for _, data in replies}), 1)
        trip = self.call('GET', '/api/trips/current')['trip']
        path = '/api/trips/' + trip['trip_id']
        bodies = [dict(request_id=uuid4().hex, expected_state_version=trip['state_version'],
                       incident_id=iid, staff_id='staff-3') for iid in ('luggage-1', 'blanket-1')]
        replies = self.race(path + '/assignments', bodies)
        self.assertEqual(sorted(code for code, _ in replies), [200, 409])
        self.assertEqual(next(data['error'] for code, data in replies if code == 409), 'state_version_conflict')
        winning_index = next(i for i, (code, _) in enumerate(replies) if code == 200)
        # Repeated response survives process death and cannot repeat assignment.
        self.stop(hard=True); self.launch()
        self.assertEqual(self.call('POST', path + '/assignments', bodies[winning_index]), replies[winning_index][1])
        trip = self.call('GET', '/api/trips/current')['trip']
        losing = dict(bodies[1-winning_index], request_id='busy', expected_state_version=trip['state_version'])
        self.assertEqual(self.call('POST', path + '/assignments', losing, status=409)['error'], 'staff_busy')
        self.assertEqual(sum(e['type'] == 'assignment' for e in trip['events']), 1)
        # Separate player guarantees luggage is resolving for the action race.
        self.player = uuid4().hex
        trip = self.start(simulation_mode='full_b4')
        path = '/api/trips/' + trip['trip_id']
        for operation, fields in [('assignments', {'staff_id': 'staff-3'}), ('dialog/open', {})]:
            trip = self.call('POST', path + '/' + operation, dict(request_id=uuid4().hex,
                expected_state_version=trip['state_version'], incident_id='luggage-1', **fields))['trip']
        bodies = [dict(request_id=uuid4().hex, expected_state_version=trip['state_version'],
                       incident_id='luggage-1', node_id='opening', action_id=action)
                  for action in ('offer_help', 'allow_luggage')]
        replies = self.race(path + '/actions', bodies)
        self.assertEqual(sorted(code for code, _ in replies), [200, 409])
        trip = self.call('GET', path)['trip']
        self.assertEqual(len(trip['history']), 1)
        winner = next(i for i, (code, _) in enumerate(replies) if code == 200)
        duplicate = self.race(path + '/actions', [bodies[winner]] * 8)
        self.assertTrue(all(code == 200 and data == replies[winner][1] for code, data in duplicate))
        self.assertEqual(len(self.call('GET', path)['trip']['history']), 1)

    def test_full_trip_active_movement_and_service_hard_restart(self):
        trip = self.start(simulation_mode='full_b4')
        path = '/api/trips/' + trip['trip_id']
        body = dict(request_id='blanket', expected_state_version=trip['state_version'], incident_id='blanket-1', staff_id='staff-1')
        assigned = self.call('POST', path + '/assignments', body)
        self.tick(2)
        before = self.call('GET', path)
        self.assertEqual(before['trip']['staff'][0]['state'], 'moving')
        self.stop(hard=True); self.launch()
        self.assertEqual(self.call('GET', path), before)
        self.assertEqual(self.call('POST', path + '/assignments', body), assigned)
        self.tick(2)
        before = self.call('GET', path)
        self.assertEqual(before['trip']['staff'][0]['state'], 'serving')
        self.stop(hard=True); self.launch()
        self.assertEqual(self.call('GET', path), before)
        self.tick(20)
        trip = self.call('GET', path)['trip']
        self.assertEqual(trip['staff'][0]['state'], 'free')
        self.assertEqual(sum(h['incident_id'] == 'blanket-1' for h in trip['history']), 1)

    def test_full_trip_lost_committed_action_then_profile_settlement(self):
        trip = self.start(simulation_mode='full_b4')
        path = '/api/trips/' + trip['trip_id']
        for operation, fields in [('assignments', {'staff_id': 'staff-3'}), ('dialog/open', {})]:
            trip = self.call('POST', path + '/' + operation, dict(request_id=uuid4().hex,
                expected_state_version=trip['state_version'], incident_id='luggage-1', **fields))['trip']
        body = dict(request_id='lost-b6', expected_state_version=trip['state_version'],
                    incident_id='luggage-1', node_id='opening', action_id='allow_luggage')
        sock = self.held_request(path + '/actions', body)
        self.stop(hard=True); self.assert_disconnected(sock); self.launch()
        reply = self.call('POST', path + '/actions', body)
        self.assertEqual(len(reply['trip']['history']), 1)
        self.tick(360)
        profile = self.call('GET', '/api/profile')['profile']
        report = self.call('GET', path + '/report')['report']
        self.assertEqual(profile['total_points'], report['points']['earned'])
        self.assertEqual(profile['total_points'], 10)
        self.assertEqual(self.call('POST', path + '/actions', body), reply)
        self.assertEqual(self.call('GET', '/api/profile')['profile'], profile)
        self.assertEqual(self.call('GET', '/api/notifications')['total'], 1)


class B6ProductionHTTPTests(ServerCase):
    # Also exercise the production listener and ordinary wall clock, without
    # clock injection/crash gates. All selected movements are instantaneous.
    race = B6HTTPTests.race
    test_concurrent_commands = B6HTTPTests.test_full_trip_concurrent_start_assignment_and_choices


class B6BackupTests(unittest.TestCase):
    def setUp(self):
        self.h = test_b4.B4Case('runTest')
        self.h.setUp()
        self.addCleanup(self.h.doCleanups)

    def test_live_wal_backup_active_pause_and_restore_preserve_dedup(self):
        h = self.h
        h.assign(); h.command('dialog/open'); body = h.action('offer_help')
        # Keep connection open and disable auto checkpoint: committed data lives
        # in WAL, so this specifically tests the online-backup guarantee.
        with closing(h.store.connect()) as writer:
            writer.execute('PRAGMA wal_autocheckpoint=0')
            writer.execute('UPDATE players SET current_trip_id=current_trip_id')
            self.assertTrue(Path(str(h.path) + '-wal').exists())
            backup = h.path.parent / 'backup.sqlite3'
            check = snapshot(h.path, backup)
            self.assertEqual(check['integrity_check'], 'ok')
            self.assertFalse(Path(str(backup) + '-wal').exists())
        restored_path = h.path.parent / 'restore' / 'demo.sqlite3'
        snapshot(backup, restored_path)
        restored = Store(restored_path, clock_ms=h.clock)
        self.assertEqual(restored.get(h.player), h.store.get(h.player))
        path = '/api/trips/' + h.trip['trip_id'] + '/actions'
        self.assertEqual(restored.mutate(h.player, path, body, h.trip['trip_id']),
                         h.store.mutate(h.player, path, body, h.trip['trip_id']))
        h.store = restored
        h.action('place_free'); h.action('confirm_clear'); h.until(360)
        self.assertEqual(h.store.progress(h.player)['profile']['completed_trips'], 1)

    def test_completed_snapshot_all_tables_equal_and_no_repeat_awards(self):
        h = self.h; h.full()
        target = h.path.parent / 'copy.sqlite3'
        snapshot(h.path, target)
        restored = Store(target, clock_ms=h.clock)
        for operation in ('profile', 'leaderboard', 'notifications'):
            self.assertEqual(restored.progress(h.player, operation), h.store.progress(h.player, operation))
        before = h.store.get(h.player, report=True)
        path = '/api/trips/' + h.trip['trip_id'] + '/complete'
        for rid in ('one', 'one', 'two'):
            self.assertEqual(restored.mutate(h.player, path, {'request_id': rid}, h.trip['trip_id']), before)
        self.assertEqual(restored.progress(h.player)['profile']['total_points'], 170)
        with closing(restored.connect()) as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM settlements').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM achievements').fetchone()[0], 3)

    def test_refuse_overwrite_same_source_missing_invalid_and_orphan_wal(self):
        h = self.h
        before = h.path.read_bytes()
        with self.assertRaises(FileExistsError): snapshot(h.path, h.path)
        self.assertEqual(h.path.read_bytes(), before)
        target = h.path.parent / 'target.db'
        target.write_bytes(b'preserved')
        with self.assertRaises(FileExistsError): snapshot(h.path, target)
        self.assertEqual(target.read_bytes(), b'preserved')
        missing = h.path.parent / 'missing.db'
        with self.assertRaises(FileNotFoundError): snapshot(missing, h.path.parent / 'unused.db')
        self.assertFalse(missing.exists())
        broken = h.path.parent / 'broken.db'; broken.write_bytes(b'broken')
        with self.assertRaises(sqlite3.DatabaseError): snapshot(broken, missing)
        self.assertFalse(missing.exists())
        orphan = Path(str(missing) + '-wal'); orphan.write_bytes(b'preserve WAL')
        with self.assertRaises(FileExistsError): snapshot(h.path, missing)
        self.assertEqual(orphan.read_bytes(), b'preserve WAL')
        self.assertFalse(list(h.path.parent.glob('.sqlite-snapshot-*')))

    def test_restored_schema_one_migrates_without_touching_backup(self):
        h = self.h
        old = h.path.parent / 'schema1.db'
        migration = Path(__file__).resolve().parents[1] / 'migrations/001_initial.sql'
        with closing(sqlite3.connect(old)) as db:
            db.executescript(migration.read_text())
        target = h.path.parent / 'schema2.db'
        snapshot(old, target)
        Store(target)
        with closing(sqlite3.connect(old)) as db:
            self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0], 1)
        with closing(sqlite3.connect(target)) as db:
            self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0], 2)
