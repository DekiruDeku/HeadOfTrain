"""Create isolated A5 HTTP fixtures and a runnable test DB. Never use a live DB."""
import argparse
from contextlib import closing
from functools import partial
from http.server import ThreadingHTTPServer
from pathlib import Path
import sqlite3
import sys
import tempfile
import threading

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from backend.demo_b4 import Demo, Clock, QuietHandler, write
from backend.storage import Store


def record(output):
    output.mkdir(parents=True,exist_ok=True)
    target=output/'test-profiles.sqlite3'
    if target.exists():
        raise SystemExit('Output database already exists; choose a new --output directory.')
    with tempfile.TemporaryDirectory() as tmp:
        clock=Clock()
        server=ThreadingHTTPServer(('127.0.0.1',0),partial(QuietHandler,directory=tmp))
        server.store=Store(Path(tmp)/'b5.sqlite3',clock_ms=clock)
        thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
        results=[]; profiles=[]
        try:
            demo=Demo(server,clock); demo.player='b5000000000000000000000000000001'
            for op in ('profile','leaderboard','notifications'):
                write(output/'fixtures'/'empty'/(op+'.json'),dict(fixture_only=True,response=demo.call('GET','/api/'+op)))
            for name,kind,expected in [('incorrect','incorrect',70),('repeat-equal','incorrect',0),('improved','correct',100),('repeat-best','correct',0),('repeat-worse','missed',0)]:
                demo.exchanges=[]; demo.snapshots={}
                report=demo.run(kind,{} if name=='incorrect' else dict(new_attempt=True))
                assert report['points']['awarded']==expected,report['points']
                complete=demo.call('POST','/api/trips/'+demo.trip['trip_id']+'/complete',dict(request_id='complete-'+name))
                assert complete['report']==report
                for op in ('profile','leaderboard','notifications'):
                    write(output/'fixtures'/name/(op+'.json'),dict(fixture_only=True,response=demo.call('GET','/api/'+op)))
                write(output/'fixtures'/name/'report.json',dict(fixture_only=True,response=complete))
                write(output/'http-exchanges'/(name+'.json'),dict(clock='injected_server_clock',player_id=demo.player,exchanges=demo.exchanges))
                results.append(dict(path=name,trip_id=report['trip_id'],points=report['points'],achievements_unlocked=report['achievements_unlocked']))
            primary=demo
            profiles.append(dict(player_id=primary.player,is_demo=False,label='Основной тестовый участник; результат реальных HTTP-команд, не импорт очков'))
            # Seed records are created through real play, then explicitly marked demo.
            groups=[('crew-demo-1','depot-demo-1','company-demo-1'),('crew-demo-2','depot-demo-1','company-demo-1'),
                    ('crew-demo-3','depot-demo-2','company-demo-1'),('crew-demo-4','depot-demo-3','company-demo-2')]
            for idx,group in enumerate(groups,2):
                demo=Demo(server,clock); demo.player='b5'+format(idx,'030x')
                report=demo.run('correct' if idx%2==0 else 'missed',dict(luggage_space='occupied',relocation='unavailable',seat_reason='intentional'))
                with closing(server.store.connect()) as db:
                    db.execute('UPDATE profiles SET display_name=?,is_demo=1,crew_id=?,depot_id=?,company_id=? WHERE player_id=?',
                               ('Демо-участник '+str(idx),*group,demo.player))
                profiles.append(dict(player_id=demo.player,is_demo=True,crew_id=group[0],depot_id=group[1],company_id=group[2],trip_id=report['trip_id']))
                write(output/'http-exchanges'/('demo-'+str(idx)+'.json'),dict(clock='injected_server_clock',player_id=demo.player,exchanges=demo.exchanges))
                write(output/'fixtures'/('demo-'+str(idx))/'report.json',dict(fixture_only=True,response={'ok':True,'api_version':'v1','report':report}))
            for scope,n in [('crew',2),('depot',3),('company',4)]:
                for page in range(1,n+2):
                    response=primary.call('GET',f'/api/leaderboard?scope={scope}&page={page}&page_size=1')
                    assert response['total']==n
                    write(output/'fixtures'/'leaderboards'/f'{scope}-{page}.json',dict(fixture_only=True,response=response))
            write(output/'profiles.json',profiles)
            write(output/'results.json',dict(clock='injected_server_clock',paths=results,profiles=len(profiles),browser_tested=False))
            # SQLite backup includes committed WAL data; target remains self-contained.
            with closing(server.store.connect()) as src, closing(sqlite3.connect(target)) as dst:
                src.backup(dst)
            before=primary.call('GET','/api/profile')
            server.store=Store(target,clock_ms=clock)
            assert primary.call('GET','/api/profile')==before
            for result in results:
                r=primary.call('GET','/api/trips/'+result['trip_id']+'/report')['report']
                assert r['points']==result['points']
            write(output/'restart-check.json',dict(profile_unchanged=True,old_reports_verified=len(results),database='test-profiles.sqlite3'))
            print('PASS: 9 HTTP trips, repeat deltas 70 / 0 / 100 / 0 / 0; 5 profiles; 3 filters; restart and old reports.')
        finally:
            server.shutdown();server.server_close();thread.join(timeout=5)
        with closing(sqlite3.connect(target)) as db:
            db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
            db.execute('PRAGMA journal_mode=DELETE')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path('docs/api/b5/recorded'))
    record(parser.parse_args().output)
