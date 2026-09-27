"""B5 public HTTP, actual process restarts and lost completion replies."""
from uuid import uuid4
from backend.tests.test_b2 import ServerCase
from backend.tests import test_b3_http, test_b4_http


class B5HTTPTests(ServerCase):
    launch=test_b3_http.B3HTTPTests.launch
    tick=test_b3_http.B3HTTPTests.tick
    command=test_b3_http.B3HTTPTests.command
    get_trip=test_b3_http.B3HTTPTests.get_trip

    def test_successful_trip_profile_ranking_and_killed_completion_reply(self):
        test_b4_http.B4HTTPTests.test_http_schedule_restart_and_report_history(self)
        trip=self.get_trip(); path='/api/trips/'+trip['trip_id']+'/complete'
        profile=self.call('GET','/api/profile')['profile']
        self.assertEqual(profile['total_points'],170)
        rank=self.call('GET','/api/leaderboard?scope=crew&page=1&page_size=1')
        self.assertTrue(rank['entries'][0]['is_self'])
        self.assertFalse(rank['entries'][0]['is_demo'])
        self.assertEqual(rank['entries'][0]['total_points'],170)
        body={'request_id':'lost-completion'}
        sock=self.held_request(path,body); self.stop(hard=True); self.assert_disconnected(sock); self.launch()
        r=self.call('POST',path,body)
        self.assertEqual(r,self.call('POST',path,{'request_id':'another-completion'}))
        self.assertEqual(self.call('GET','/api/profile')['profile'],profile)
        self.assertEqual(self.call('GET','/api/notifications')['total'],1)
        self.call('POST',path,{'request_id':'foreign'},player=uuid4().hex,status=404)

    def test_kill_before_completion_commit_and_recover(self):
        trip=self.start(simulation_mode='full_b4'); self.tick(360)
        path='/api/trips/'+trip['trip_id']+'/complete'
        body={'request_id':'hold-before-commit'}
        sock=self.held_request(path,body,expected='UNCOMMITTED')
        self.stop(hard=True); self.assert_disconnected(sock); self.launch()
        # A different request settles the rolled-back trip exactly once.
        result=self.call('POST',path,{'request_id':'recover'})
        self.assertEqual(result['report']['achievements_unlocked'],['first_trip'])
        self.assertEqual(self.call('GET','/api/profile')['profile']['completed_trips'],1)
        self.assertEqual(self.call('GET','/api/notifications')['total'],1)

    def test_empty_errors_identity_and_pagination(self):
        self.assertEqual(self.call('GET','/api/profile')['profile']['total_points'],0)
        self.assertEqual(self.call('GET','/api/notifications')['notifications'],[])
        self.assertEqual(self.call('GET','/api/leaderboard')['entries'],[])
        for query in ('scope=unknown','page=0','page_size=51','page=-1','page=1&page=2','crew_id=other','page=abc','page_size='):
            self.assertEqual(self.call('GET','/api/leaderboard?'+query,status=400)['error'],'invalid_query')
        self.call('GET','/api/profile?extra=1',status=400)
        self.call('POST','/api/profile',{},status=405)
        trip=self.start(simulation_mode='full_b4'); path='/api/trips/'+trip['trip_id']
        self.call('POST',path+'/complete',{'request_id':'early'},status=409)
        self.call('GET',path+'/report',status=409)
        self.tick(360)
        self.call('POST',path+'/complete',{'request_id':'score','points':100},status=400)
        self.call('GET',path+'/report',player=uuid4().hex,status=404)
        self.assertEqual(self.call('GET','/api/profile')['profile']['completed_trips'],1)
        self.assertEqual(self.call('GET','/api/leaderboard?page=2&page_size=1')['entries'],[])
        self.assertEqual(self.call('GET','/api/notifications?page=2&page_size=1')['notifications'],[])
