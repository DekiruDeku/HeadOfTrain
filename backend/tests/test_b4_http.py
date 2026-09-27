"""Actual HTTP and killed/restarted server, including a lost committed reply."""
from uuid import uuid4
from backend.tests.test_b2 import ServerCase
from backend.tests import test_b3_http as b3_http


class B4HTTPTests(ServerCase):
    launch=b3_http.B3HTTPTests.launch
    tick=b3_http.B3HTTPTests.tick
    command=b3_http.B3HTTPTests.command
    get_trip=b3_http.B3HTTPTests.get_trip

    def test_http_schedule_restart_and_report_history(self):
        trip=self.start(simulation_mode='full_b4')
        trip=self.command(trip,'assignments',staff_id='staff-1',incident_id='blanket-1')
        trip=self.command(trip,'assignments',staff_id='staff-3')
        trip=self.command(trip,'dialog/open')
        self.tick(10)
        self.stop(hard=True)
        self.launch()
        trip=self.get_trip()
        self.assertEqual(trip['simulation_time'],0)
        self.assertEqual(trip['dialog']['critical_decision_time'],35)
        trip=self.act(trip,'offer_help')
        trip=self.act(trip,'place_free')
        trip=self.act(trip,'confirm_clear')
        self.tick(100)
        trip=self.get_trip()
        self.assertEqual(len(trip['incidents']),3)
        self.assertEqual(trip['incidents'][1]['resolution'],'served')
        trip=self.command(trip,'assignments',staff_id='staff-1',incident_id='children-1')
        trip=self.command(trip,'dialog/open',incident_id='children-1')
        for a in ('clarify','offer_move','verify_agreement'):
            trip=self.command(trip,'actions',incident_id='children-1',node_id=trip['dialog']['node_id'],action_id=a)
        self.tick(100)
        trip=self.command(self.get_trip(),'assignments',staff_id='staff-2',incident_id='table-1')
        self.tick(60)
        trip=self.command(self.get_trip(),'assignments',staff_id='staff-2',incident_id='seat-1')
        trip=self.command(trip,'dialog/open',incident_id='seat-1')
        for a in ('check_ticket','guide','verify_seats'):
            trip=self.command(trip,'actions',incident_id='seat-1',node_id=trip['dialog']['node_id'],action_id=a)
        self.tick(100)
        trip=self.get_trip()
        self.assertEqual(trip['outcome'],'successful')
        report=self.call('GET','/api/trips/'+trip['trip_id']+'/report')['report']
        self.assertEqual(len(report['history']),11)
        self.stop(hard=True)
        self.tick(1000)
        self.launch()
        self.assertEqual(self.call('GET','/api/trips/'+trip['trip_id']+'/report')['report'],report)

    def test_lost_action_reply_and_deadline_commit_once(self):
        trip=self.start(simulation_mode='full_b4')
        trip=self.command(trip,'assignments',staff_id='staff-3')
        trip=self.command(trip,'dialog/open')
        path='/api/trips/'+trip['trip_id']+'/actions'
        body=dict(request_id='b4-lost',expected_state_version=trip['state_version'],incident_id='luggage-1',node_id='opening',action_id='allow_luggage')
        sock=self.held_request(path,body)
        self.stop(hard=True)
        self.assert_disconnected(sock)
        self.tick(360)
        self.launch()
        replay=self.call('POST',path,body)
        self.assertEqual(replay['trip']['scales']['safety'],80)
        result=self.get_trip()
        self.assertEqual(result['status'],'completed')
        self.assertEqual(len(result['history']),5)
        self.assertEqual(self.call('POST',path,body),replay)
        self.assertEqual(self.get_trip(),result)

    def test_http_invalid_condition_ownership_and_clock_rejected(self):
        trip=self.start(simulation_mode='full_b4')
        self.call('POST','/api/trips/start',dict(request_id=uuid4().hex,simulation_mode='full_b4',seat_reason='invented'),status=400)
        path='/api/trips/'+trip['trip_id']+'/assignments'
        body=dict(request_id=uuid4().hex,expected_state_version=trip['state_version'],incident_id='luggage-1',staff_id='staff-3')
        self.call('POST',path,{**body,'elapsed':0},status=400)
        self.call('POST',path,body,player=uuid4().hex,status=404)
        self.tick(75)
        self.assertEqual(self.call('POST',path,body,status=409)['error'],'state_version_conflict')
        self.assertEqual(len(self.get_trip()['history']),1)
