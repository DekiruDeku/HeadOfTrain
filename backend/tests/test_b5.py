"""Progress invariants; all DBs are temporary, production data is never opened."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from copy import deepcopy
import json
import sqlite3
import unittest
from uuid import uuid4
from backend.tests import test_b4
from backend.storage import Store, APIError, encode
from backend import progress_b5


class B5Tests(unittest.TestCase):
    def setUp(self):
        self.h = test_b4.B4Case('runTest')
        self.h.setUp()
        self.addCleanup(self.h.doCleanups)

    def profile(self):
        return self.h.store.progress(self.h.player)['profile']

    def report(self):
        return self.h.store.get(self.h.player,report=True)['report']

    def repeat(self, **extra):
        h=self.h
        h.trip=h.store.mutate(h.player,'/api/trips/start',dict(request_id=uuid4().hex,simulation_mode='full_b4',new_attempt=True,**extra))['trip']

    def test_correct_exact_scores_scales_evidence_and_profile(self):
        self.h.full()
        r=self.report()
        self.assertEqual(r['points'],dict(earned=170,awarded=170,previous_total=0,total_after=170))
        self.assertEqual({c['id']:c['points'] for c in r['competencies']},dict(communication=50,safety=20,prioritization=100))
        self.assertEqual(r['scales'], self.h.trip['scales'])
        self.assertEqual(len(r['resolved_incident_ids']),5)
        self.assertFalse(r['missed_incident_ids'] or r['unresolved_incident_ids'])
        self.assertEqual(len(r['achievements_unlocked']),3)
        p=self.profile()
        self.assertEqual(p['total_points'],170)
        self.assertEqual(len(p['best_results']),5)
        self.assertTrue(all(a['earned'] for a in p['achievements']))
        self.assertEqual(p['content'][2]['status'],'future_content')
        self.assertFalse(p['content'][2]['playable'])
        self.assertTrue(all(e['history_indices'] or e['event_ids'] for c in r['competencies'] for e in c['evidence']))
        for s in r['scenario_scores']:
            if s['scenario_id'] != 'luggage-in-aisle':self.assertNotIn('safety',s['competencies'])
            if s['scenario_id'].startswith('service:'):self.assertEqual(set(s['competencies']),{'prioritization'})

    def test_missed_all_does_not_award_vacuous_achievements(self):
        self.h.until(360)
        r=self.report()
        self.assertEqual(r['points']['earned'],0)
        self.assertEqual(r['achievements_unlocked'],['first_trip'])
        self.assertEqual(len(r['missed_incident_ids']),5)
        self.assertEqual(r['scales']['safety'],85)
        self.assertIn('багажа',r['recommendation'])
        self.assertFalse(r['recommendation_evidence'][0]['met'])
        self.assertEqual(len(self.h.store.progress(self.h.player,'notifications')['notifications']),1)

    def test_repeat_equal_worse_improved_and_old_report_stable(self):
        h=self.h
        h.assign('blanket-1','staff-1'); h.assign(); h.solve('luggage-1',['allow_luggage']); h.until(360)
        old=self.report(); tid=h.trip['trip_id']
        self.assertEqual(old['points']['earned'],30)  # blanket 20 + timely luggage arrival 10
        self.repeat(); h.full()
        improved=self.report()
        self.assertEqual(improved['points']['awarded'],140)
        self.repeat(); h.full()
        equal=self.report()
        self.assertEqual(equal['points']['awarded'],0)
        self.assertFalse(equal['achievements_unlocked'] or equal['unlocks'] or equal['notification_ids'])
        self.repeat(); h.until(360)
        self.assertEqual(self.report()['points']['awarded'],0)
        self.assertEqual(self.profile()['total_points'],170)
        self.assertEqual(self.profile()['completed_trips'],4)
        self.assertEqual(h.store.get(h.player,tid,report=True)['report'],old)
        self.assertEqual(h.store.progress(h.player,'leaderboard')['entries'][0]['total_points'],170)

    def test_concurrent_completion_same_and_different_requests(self):
        h=self.h; h.clock.step(360)
        path='/api/trips/'+h.trip['trip_id']+'/complete'
        def finish(i):
            return h.store.mutate(h.player,path,{'request_id':'finish-'+str(i%4)},h.trip['trip_id'])
        with ThreadPoolExecutor(max_workers=8) as pool:
            replies=list(pool.map(finish,range(24)))
        self.assertTrue(all(r==replies[0] for r in replies))
        with closing(h.store.connect()) as db:
            for table in ('settlements','achievements','content_unlocks','notifications'):
                self.assertEqual(db.execute('SELECT COUNT(*) FROM '+table).fetchone()[0],1)
        self.assertEqual(self.profile()['completed_trips'],1)

    def test_restart_and_history_projection_ignores_cached_outcomes(self):
        h=self.h; h.full(); before=self.report(); p=self.profile()
        with closing(h.store.connect()) as db:
            row=db.execute('SELECT * FROM trips').fetchone()
        state=json.loads(row['state_json']); bundle=json.loads(row['scenario_json'])
        state['scales']={}; state['facts']={}; state['critical_marks']=['FAKE']; state['outcome']='fake'
        state['incidents']=[]
        rebuilt=progress_b5.report(state,bundle)
        for k in ('scales','facts','critical_marks','outcome','competencies','history','recommendation'):
            self.assertEqual(rebuilt[k],before[k])
        h.store=Store(h.path,clock_ms=h.clock)
        self.assertEqual(self.report(),before); self.assertEqual(self.profile(),p)

    def test_failed_settlement_rolls_back_all_writes(self):
        h=self.h
        with closing(h.store.connect()) as db:
            db.execute("CREATE TRIGGER reject_settlement BEFORE INSERT ON settlements BEGIN SELECT RAISE(ABORT,'injected failure'); END")
        h.clock.step(360)
        with self.assertRaises(sqlite3.IntegrityError):h.store.get(h.player)
        with closing(h.store.connect()) as db:
            self.assertEqual(json.loads(db.execute('SELECT state_json FROM trips').fetchone()[0])['status'],'in_progress')
            for t in ('best_results','achievements','content_unlocks','notifications','settlements'):
                self.assertEqual(db.execute('SELECT COUNT(*) FROM '+t).fetchone()[0],0)
            db.execute('DROP TRIGGER reject_settlement')
        h.get(); self.assertEqual(self.profile()['completed_trips'],1)

    def test_migration_v1_backfills_once_preserves_legacy(self):
        h=self.h; h.full(); expected=self.report()
        with closing(h.store.connect()) as db:
            rows=db.execute('SELECT * FROM trips').fetchall()
        oldpath=h.path.parent/'v1.db'
        with closing(sqlite3.connect(oldpath)) as db:
            db.executescript((__import__('pathlib').Path('backend/migrations/001_initial.sql')).read_text())
            db.execute('INSERT INTO players VALUES (?,?)',(h.player,h.trip['trip_id']))
            for row in rows:db.execute('INSERT INTO trips VALUES (?,?,?,?,?)',tuple(row))
            db.commit()
        h.store=Store(oldpath,clock_ms=h.clock)
        self.assertEqual(self.report(),expected)
        h.store=Store(oldpath,clock_ms=h.clock)
        self.assertEqual(self.profile()['total_points'],170)
        self.assertEqual(self.profile()['completed_trips'],1)

    def test_promise_then_repair_disqualifies_check_achievement(self):
        h=self.h; h.assign(); h.solve('luggage-1',['offer_help','place_free','confirm_clear'])
        h.until(100); h.assign('children-1','staff-1'); h.get(4)
        h.solve('children-1',['promise_move','fulfil_promise','verify_agreement'])
        h.until(260); h.assign('seat-1','staff-2'); h.get(4)
        h.solve('seat-1',['check_ticket','guide','verify_seats']); h.until(360)
        r=self.report()
        self.assertIn('safety_resolved',r['eligible_achievements'])
        self.assertNotIn('checked_before_promise',r['eligible_achievements'])
        e=next(e for c in r['competencies'] for e in c['evidence'] if e['incident_id']=='children-1' and e['criterion']=='check_before_promise')
        self.assertFalse(e['met'])

    def test_missed_one_applicable_scenario_disqualifies_checks(self):
        h=self.h; h.assign(); h.solve('luggage-1',['offer_help','place_free','confirm_clear']); h.until(360)
        self.assertNotIn('checked_before_promise',self.report()['eligible_achievements'])
        self.assertIn('safety_resolved',self.report()['eligible_achievements'])

    def test_filters_pages_demo_flags_and_ties(self):
        h=self.h; players=[]
        for crew,depot,company in [('c1','d1','co1'),('c1','d1','co1'),('c2','d1','co1'),('c3','d2','co1'),('c4','d3','co2')]:
            h.start(); h.until(360); players.append(h.player)
            with closing(h.store.connect()) as db:
                db.execute('UPDATE profiles SET crew_id=?,depot_id=?,company_id=?,is_demo=1 WHERE player_id=?',(crew,depot,company,h.player))
        for scope,n in [('crew',2),('depot',3),('company',4)]:
            page=h.store.progress(players[0],'leaderboard',scope,1,1)
            self.assertEqual(page['total'],n); self.assertEqual(page['total_pages'],n)
            entries=[h.store.progress(players[0],'leaderboard',scope,p,1)['entries'][0] for p in range(1,n+1)]
            self.assertEqual([e['rank'] for e in entries],list(range(1,n+1)))
            self.assertTrue(all(e['is_demo'] for e in entries))
            self.assertEqual(sum(e['is_self'] for e in entries),1)
            self.assertEqual(h.store.progress(players[0],'leaderboard',scope,n+1,1)['entries'],[])
        self.assertEqual(h.store.progress(players[0],'notifications',page=2,page_size=1)['notifications'],[])

    def test_empty_profiles_legacy_and_invalid_parameters(self):
        h=self.h; player=uuid4().hex
        p=h.store.progress(player)['profile']
        self.assertEqual(p['total_points'],0); self.assertFalse(p['report_ids'])
        self.assertTrue(all(not a['earned'] for a in p['achievements']))
        self.assertEqual(h.store.progress(player,'leaderboard')['total_pages'],0)
        self.assertEqual(h.store.progress(player,'notifications')['notifications'],[])
        path='/api/trips/'+h.trip['trip_id']+'/complete'
        with self.assertRaises(APIError):h.store.mutate(h.player,path,{'request_id':'early'},h.trip['trip_id'])
        for kwargs in [dict(scope='invalid'),dict(page=0),dict(page_size=51),dict(page=True)]:
            with self.assertRaises(APIError):h.store.progress(player,'leaderboard',**kwargs)

    def test_rules_pinned_and_version_specific_record(self):
        h=self.h; h.full(); self.assertEqual(self.profile()['total_points'],170)
        h.store.b4_bundle['scenarios']['wrong-seat']['version']='b5-test-v2'
        self.repeat(); h.full()
        self.assertEqual(self.report()['points']['awarded'],40)
        self.assertEqual(len(self.profile()['best_results']),6)
        with closing(h.store.connect()) as db:
            bundle=json.loads(db.execute('SELECT scenario_json FROM trips WHERE trip_id=?',(h.trip['trip_id'],)).fetchone()[0])
        self.assertEqual(bundle['_progress_config']['version'],'b5-1')

    def test_corrupt_journal_rejected_instead_of_fabricating_result(self):
        h=self.h; h.full()
        with closing(h.store.connect()) as db:row=db.execute('SELECT * FROM trips').fetchone()
        state=json.loads(row['state_json']); bundle=json.loads(row['scenario_json'])
        state['history'][0]['effects']['safety_delta']=999
        with self.assertRaises(ValueError):progress_b5.report(state,bundle)

    def test_every_b4_path_has_bounded_applicable_scores_and_matching_scales(self):
        from backend.b4_paths import all_paths
        h=self.h
        for path in all_paths(h.store.b4_bundle):
            with self.subTest(scenario=path['scenario_id'],actions=path['actions']):
                h.start(**path['conditions'])
                spec=next(i for i in h.store.b4_bundle['_simulation_config']['incidents'] if i.get('scenario_id')==path['scenario_id'])
                h.until(spec['appears_at'])
                staff='staff-3' if spec['id']=='luggage-1' else 'staff-1' if spec['id']=='children-1' else 'staff-2'
                h.assign(spec['id'],staff); h.get(0 if spec['id']=='luggage-1' else 4)
                h.solve(spec['id'],path['actions']); h.until(360)
                r=self.report(); score=next(s for s in r['scenario_scores'] if s['incident_id']==spec['id'])
                self.assertEqual(r['scales'],h.trip['scales'])
                self.assertEqual(r['critical_marks'],h.trip['critical_marks'])
                self.assertEqual(spec['id'] in r['resolved_incident_ids'],path['successful'])
                self.assertEqual(score['max_points'],50 if spec['id']=='luggage-1' else 40)
                self.assertTrue(0 <= score['points'] <= score['max_points'])
                self.assertEqual(sum(score['competencies'].values()),score['points'])
                self.assertEqual(r['points']['awarded'],r['points']['earned'])
                self.assertTrue(all(e['reason'] and e['recommendation'] for e in score['evidence']))

    def test_upgrade_pins_rules_for_existing_active_b4(self):
        h=self.h
        with closing(h.store.connect()) as db:
            row=db.execute('SELECT scenario_json FROM trips').fetchone()
            bundle=json.loads(row[0]); bundle.pop('_progress_config')
            db.execute('UPDATE trips SET scenario_json=?',(encode(bundle),))
        h.store=Store(h.path,clock_ms=h.clock)
        with closing(h.store.connect()) as db:
            pinned=json.loads(db.execute('SELECT scenario_json FROM trips').fetchone()[0])
        self.assertEqual(pinned['_progress_config']['version'],'b5-1')
        original=deepcopy(progress_b5.DEFAULT_RULES)
        try:
            progress_b5.DEFAULT_RULES['points_per_criterion']=999
            h.full()
            self.assertEqual(self.report()['points']['earned'],170)
        finally:
            progress_b5.DEFAULT_RULES.clear(); progress_b5.DEFAULT_RULES.update(original)
