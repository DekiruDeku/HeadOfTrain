"""B4 graph, schedule, API persistence and edge boundaries. Isolated temporary DBs."""
import json
import sqlite3
import tempfile
import unittest
from contextlib import closing
from copy import deepcopy
from itertools import product
from pathlib import Path
from uuid import uuid4
from backend.storage import Store, APIError
from backend.tests.test_b3 import Clock
from backend.b4_paths import all_paths, correct_actions
from backend import trip_b4


class B4Case(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.clock=Clock()
        self.path=Path(self.temp.name)/'b4.sqlite3'
        self.store=Store(self.path,clock_ms=self.clock)
        self.player=uuid4().hex
        self.trip=self.start()

    def start(self,**extra):
        self.player=uuid4().hex
        self.trip=self.store.mutate(self.player,'/api/trips/start',dict(request_id=uuid4().hex,simulation_mode='full_b4',**extra))['trip']
        return self.trip

    def get(self,seconds=0):
        self.clock.step(seconds)
        self.trip=self.store.get(self.player)['trip']
        return self.trip

    def until(self,seconds):
        self.get(seconds-self.trip['simulation_time'])

    def command(self,op,incident='luggage-1',**fields):
        body=dict(request_id=uuid4().hex,expected_state_version=self.trip['state_version'],incident_id=incident,**fields)
        self.trip=self.store.mutate(self.player,'/api/trips/'+self.trip['trip_id']+'/'+op,body,self.trip['trip_id'])['trip']
        return body

    def assign(self,incident='luggage-1',staff='staff-3'):
        return self.command('assignments',incident,staff_id=staff)

    def action(self,id,incident='luggage-1',read=0):
        self.get(read)
        return self.command('actions',incident,node_id=self.trip['dialog']['node_id'],action_id=id)

    def item(self,id='luggage-1'):
        return next(i for i in self.trip['incidents'] if i['id']==id)

    def solve(self,incident,actions,read=0):
        self.command('dialog/open',incident)
        for a in actions:
            self.action(a,incident,read)

    def full(self,read=10):
        actions=correct_actions(self.trip['conditions'])
        self.assign('blanket-1','staff-1')
        self.assign()
        self.solve('luggage-1',actions['luggage-1'],read)
        self.until(100)
        self.assign('children-1','staff-1')
        self.solve('children-1',actions['children-1'],read)
        self.until(200)
        self.assign('table-1','staff-2')
        self.until(260)
        self.assign('seat-1','staff-2')
        self.solve('seat-1',actions['seat-1'],read)
        self.until(360)
        return self.trip

    def test_all_eight_conditions_success_and_450_second_wall_budget(self):
        for values in product(['free','occupied'],['available','unavailable'],['mistake','intentional']):
            with self.subTest(values=values):
                self.start(**dict(zip(['luggage_space','relocation','seat_reason'],values)))
                began=self.clock.ms
                result=self.full()
                self.assertEqual(result['outcome'],'successful')
                self.assertEqual(result['simulation_time'],360)
                self.assertEqual(self.clock.ms-began,450000)
                self.assertEqual(len(result['history']),11)
                self.assertEqual(len(result['incidents']),5)
                self.assertEqual(result['critical_marks'],[])
                self.assertEqual(result['scales']['safety'],100)
                self.assertEqual(len(result['completed_participant_ids']),7)
                self.assertTrue(all(i['resolution'] in ('resolved','served') for i in result['incidents']))
                r=self.store.get(self.player,report=True)['report']
                self.assertEqual(r['history'],result['history'])
                self.assertEqual(r['events'],result['events'])
                self.store=Store(self.path,clock_ms=self.clock)
                self.clock.step(900)
                self.assertEqual(self.store.get(self.player,report=True)['report'],r)

    def test_every_available_graph_path_executes_with_expected_deltas(self):
        bundle=self.store.b4_bundle
        for p in all_paths(bundle):
            with self.subTest(scenario=p['scenario_id'],actions=p['actions'],conditions=p['conditions']):
                self.start(**p['conditions'])
                spec=next(i for i in bundle['_simulation_config']['incidents'] if i.get('scenario_id')==p['scenario_id'])
                self.until(spec['appears_at'])
                staff='staff-3' if spec['id']=='luggage-1' else 'staff-1' if spec['id']=='children-1' else 'staff-2'
                self.assign(spec['id'],staff)
                self.get(0 if spec['id']=='luggage-1' else 4)
                before=deepcopy(self.trip['scales'])
                self.solve(spec['id'],p['actions'])
                self.assertEqual(self.item(spec['id'])['resolution'],p['outcome'])
                self.assertEqual(self.trip['scales']['safety']-before['safety'],p['effects']['safety_delta'])
                for participant in spec['participant_ids']:
                    self.assertEqual(self.trip['scales']['loyalty'][participant]-before['loyalty'][participant],p['effects']['loyalty_deltas'].get(participant,0))
                h=[h for h in self.trip['history'] if h['incident_id']==spec['id']]
                self.assertEqual([h['action_id'] for h in h],p['actions'])
                self.assertTrue(all(h['explanation'] and h['scenario_version'] for h in h))

    def test_schedule_exact_boundary_and_simultaneous_calls(self):
        self.assertEqual([i['id'] for i in self.trip['incidents']],['luggage-1','blanket-1'])
        self.assertEqual([e['simulation_time'] for e in self.trip['events']],[0,0])
        self.get(99.999)
        self.assertEqual(len(self.trip['incidents']),2)
        self.get(.001)
        self.assertEqual(self.item('children-1')['reaction_time'],90)
        self.assertEqual(self.trip['next_incident_time'],200)

    def test_all_missed_and_idle_trip_waits_to_360(self):
        self.get(360)
        self.assertEqual(self.trip['status'],'completed')
        self.assertEqual(len(self.trip['history']),5)
        self.assertEqual(self.trip['scales']['safety'],85)
        self.assertEqual(self.trip['outcome'],'completed_with_issues')
        self.assertEqual([e['simulation_time'] for e in self.trip['events'] if e['type']=='incident_appeared'],[0,0,100,200,260])
        self.assertEqual([h['simulation_time'] for h in self.trip['history']],[75,90,190,300,350])

    def test_critical_timeout_unpauses_and_does_not_repeat(self):
        self.assign()
        self.command('dialog/open')
        self.get(44.999)
        self.assertEqual(self.trip['simulation_time'],0)
        self.get(.001)
        self.assertEqual(self.item()['resolution'],'decision_timeout')
        self.assertFalse(self.trip['paused'])
        self.get(360)
        self.assertEqual(sum(h['action_id']=='decision_timeout' for h in self.trip['history']),1)

    def test_paused_dialog_freezes_schedule_and_other_decision(self):
        # Luggage noncritical placement can keep resolving until another scenario arrives.
        self.assign()
        self.command('dialog/open')
        self.action('offer_help')
        self.command('dialog/close')
        self.until(100)
        self.assign('children-1','staff-1')
        self.get(4)
        self.command('dialog/open')
        self.action('place_free')
        self.command('dialog/close')
        self.command('dialog/open','children-1')
        self.get(300)
        self.assertEqual(self.trip['simulation_time'],104)
        self.assertEqual(self.item()['critical_decision_time'],30)
        self.assertEqual(len(self.trip['incidents']),3)
        self.command('dialog/close','children-1')
        self.get(30)
        self.assertEqual(self.item()['resolution'],'decision_timeout')
        self.assertEqual(self.item('children-1')['state'],'resolving')

    def test_explicit_wait_finalizes_unresolved_at_trip_end(self):
        self.assign()
        self.command('dialog/open')
        self.action('offer_help')
        self.command('dialog/close')
        self.get(360)
        self.assertEqual(self.item()['resolution'],'trip_timeout')
        self.assertEqual(self.trip['status'],'completed')
        self.assertEqual(self.trip['history'][-1]['action_id'],'trip_timeout')

    def test_service_does_not_compensate_critical_mark(self):
        self.assign('blanket-1','staff-1')
        self.assign()
        self.solve('luggage-1',['allow_luggage'])
        self.get(24)
        self.assertEqual(self.item('blanket-1')['resolution'],'served')
        self.assertEqual(self.trip['scales']['safety'],80)
        self.assertEqual(self.trip['critical_marks'],['aisle_left_blocked'])

    def test_reject_future_busy_unavailable_and_other_dialog(self):
        with self.assertRaises(APIError) as e:self.assign('children-1','staff-1')
        self.assertEqual(e.exception.data['error'],'incident_unavailable')
        self.start(luggage_space='occupied')
        self.assign()
        with self.assertRaises(APIError) as e:self.assign('blanket-1','staff-3')
        self.assertEqual(e.exception.data['error'],'staff_busy')
        self.command('dialog/open')
        self.action('offer_help')
        with self.assertRaises(APIError) as e:self.action('place_free')
        self.assertEqual(e.exception.data['error'],'action_unavailable')
        self.command('dialog/close')
        self.until(100)
        self.assign('children-1','staff-1')
        self.get(4)
        self.command('dialog/open','children-1')
        with self.assertRaises(APIError) as e:self.command('dialog/open')
        self.assertEqual(e.exception.data['error'],'another_dialog_open')
        with self.assertRaises(APIError) as e:self.command('dialog/close')
        self.assertEqual(e.exception.data['error'],'another_dialog_open')

    def test_duplicate_actions_resume_pinning_and_invalid_conditions(self):
        self.assign()
        self.command('dialog/open')
        b=self.action('allow_luggage')
        original=deepcopy(self.trip)
        self.get(30)
        replay=self.store.mutate(self.player,'/api/trips/'+self.trip['trip_id']+'/actions',b,self.trip['trip_id'])
        self.assertEqual(replay['trip'],original)
        self.get()
        self.assertEqual(len(self.trip['history']),1)
        self.store.b4_bundle['scenarios']['children-disturb']['nodes']['opening']['actions'][0]['effects']={'safety_delta':-999}
        self.until(100)
        self.assign('children-1','staff-1')
        self.get(4)
        self.command('dialog/open','children-1')
        self.action('clarify','children-1')
        self.assertEqual(self.trip['scales']['safety'],80)
        restored=self.store.mutate(self.player,'/api/trips/start',{'request_id':uuid4().hex})
        self.assertEqual(restored['trip'],self.trip)
        for value in ('bad',None,True,{}):
            with self.assertRaises(APIError):self.start(relocation=value)

    def test_coarse_and_fine_polling_equal_after_restart(self):
        self.assign('blanket-1','staff-1')
        self.assign()
        self.command('dialog/open')
        otherpath=Path(self.temp.name)/'copy.db'
        with closing(self.store.connect()) as src,closing(sqlite3.connect(otherpath)) as dst:src.backup(dst)
        otherclock=Clock()
        other=Store(otherpath,clock_ms=otherclock)
        self.get(1000)
        for _ in range(500):
            otherclock.step(2)
            result=other.get(self.player)['trip']
        self.assertEqual(result,self.trip)

    def test_all_decision_timeouts_and_reaction_arrival_tie(self):
        self.assign()
        self.command('dialog/open')
        self.action('offer_help')
        self.action('place_free')
        self.get(30)
        self.assertEqual(self.item()['resolution'],'decision_timeout')
        self.assertFalse(self.item()['facts']['aisle_clear'])
        self.start()
        self.get(57)
        self.assign(staff='staff-1')
        self.get(18)
        self.assertEqual(self.item()['resolution'],'reaction_timeout')
        self.assertEqual(self.trip['staff'][0]['state'],'free')
        self.assertEqual(self.trip['staff'][0]['route_point_id'],'c2-luggage')

    def test_each_scenario_trip_timeout_and_no_premature_completion(self):
        for incident,at,staff,travel,first in [('luggage-1',0,'staff-3',0,'offer_help'),
                ('children-1',100,'staff-1',4,'clarify'),('seat-1',260,'staff-2',4,'check_ticket')]:
            with self.subTest(incident=incident):
                self.start()
                self.until(at)
                self.assign(incident,staff)
                self.get(travel)
                self.command('dialog/open',incident)
                self.action(first,incident)
                self.command('dialog/close',incident)
                self.until(359.999)
                self.assertEqual(self.trip['status'],'in_progress')
                self.get(.001)
                self.assertEqual(self.item(incident)['resolution'],'trip_timeout')
                self.assertEqual(self.trip['status'],'completed')
                self.assertTrue(all(s['state']=='free' for s in self.trip['staff']))

    def test_public_wire_contract_and_content_provenance(self):
        states=[deepcopy(self.trip)]
        self.full()
        states.append(self.trip)
        for state in states:
            self.assertIsInstance(state['node_id'],str)
            self.assertEqual(state['simulation_mode'],'full_b4')
            self.assertEqual(state['content_status'],'draft')
            for i in state['incidents']:
                self.assertIn(i['type'],('safety','service','conflict'))
                self.assertIn(i['state'],('waiting','en_route','resolving','completed'))
            def clean(value):
                if isinstance(value,dict):
                    self.assertFalse(any(k.startswith('_') for k in value))
                    for v in value.values():clean(v)
                elif isinstance(value,list):
                    for v in value:clean(v)
            clean(state)
        r=self.store.get(self.player,report=True)['report']
        self.assertEqual(len(r['sources']),3)
        self.assertEqual(len(r['scenario_versions']),3)
        for h in r['history']:
            self.assertEqual(h['explanation_status'],'draft')
            self.assertTrue(h['explanation'])

    def test_schema_rejects_deadend_cycle_and_four_options(self):
        for defect in ('cycle','deadend','four'):
            b=deepcopy(self.store.b4_bundle)
            n=b['scenarios']['wrong-seat']['nodes']['opening']
            if defect=='cycle':n['actions'][0]['next']='opening'
            elif defect=='deadend':n['actions']=[]
            else:n['actions'].append(deepcopy(n['actions'][0]))
            with self.assertRaises(AssertionError):trip_b4.validate(b)


if __name__=='__main__':unittest.main()
