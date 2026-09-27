"""Record real HTTP B4 paths using an isolated server and a controlled server clock.
No time-travel endpoint is exposed; production server always uses wall time.
"""
import argparse
from functools import partial
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import sys
import tempfile
import threading
from urllib.request import Request, urlopen
from uuid import uuid4

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from backend.server import Handler
from backend.storage import Store
from backend.b4_paths import all_paths, correct_actions


class Clock:
    ms=1800000000000
    def __call__(self):return self.ms
    def step(self,s):self.ms+=round(s*1000)


class QuietHandler(Handler):
    def log_message(self,*args):pass


class Demo:
    def __init__(self,server,clock):
        self.url='http://127.0.0.1:'+str(server.server_port)
        self.clock=clock
        self.player=uuid4().hex
        self.exchanges=[]
        self.trip=None
        self.snapshots={}

    def call(self,method,path,body=None):
        req=Request(self.url+path,method=method,data=json.dumps(body).encode() if body is not None else None,
                    headers={'X-Demo-Player':self.player,'Content-Type':'application/json'})
        with urlopen(req,timeout=10) as reply:
            data=json.load(reply)
            self.exchanges.append(dict(method=method,path=path,body=body,status=reply.status,response=data))
        if 'trip' in data:self.trip=data['trip']
        return data

    def start(self,conditions):
        self.call('POST','/api/trips/start',dict(request_id=uuid4().hex,simulation_mode='full_b4',**conditions))
        self.snapshot('initial')

    def snapshot(self,name):self.snapshots[name]={'fixture_only':True,'response':{'ok':True,'api_version':'v1','trip':self.trip}}

    def get(self,s=0):
        self.clock.step(s)
        return self.call('GET','/api/trips/current')

    def until(self,t):self.get(t-self.trip['simulation_time'])

    def command(self,op,incident,**fields):
        return self.call('POST','/api/trips/'+self.trip['trip_id']+'/'+op,dict(request_id=uuid4().hex,
             expected_state_version=self.trip['state_version'],incident_id=incident,**fields))

    def assign(self,incident,staff):self.command('assignments',incident,staff_id=staff)

    def solve(self,incident,actions,read):
        self.command('dialog/open',incident)
        self.snapshot(incident+'-opening')
        for a in actions:
            self.get(read)
            self.command('actions',incident,node_id=self.trip['dialog']['node_id'],action_id=a)
            if self.trip['dialog']:self.snapshot(incident+'-'+self.trip['dialog']['node_id'])

    def run(self,kind,conditions):
        self.start(conditions)
        if kind=='missed':self.until(360)
        elif kind=='critical_timeout':
            self.assign('luggage-1','staff-3')
            self.command('dialog/open','luggage-1')
            self.get(45)
            self.snapshot('critical-timeout')
            self.until(360)
        else:
            good=correct_actions(self.trip['conditions'])
            actions=good if kind=='correct' else {'luggage-1':['allow_luggage'],'children-1':['blame_family'],'seat-1':['leave_seated']}
            self.assign('blanket-1','staff-1')
            self.assign('luggage-1','staff-3')
            self.solve('luggage-1',actions['luggage-1'],10)
            self.until(100)
            self.snapshot('children-appeared')
            self.assign('children-1','staff-1')
            self.solve('children-1',actions['children-1'],10)
            self.until(200)
            self.assign('table-1','staff-2')
            self.until(260)
            self.assign('seat-1','staff-2')
            self.solve('seat-1',actions['seat-1'],10)
            self.until(360)
        assert self.trip['status']=='completed'
        assert len(self.trip['incidents'])==5
        assert self.trip['outcome']==('successful' if kind=='correct' else 'completed_with_issues')
        self.snapshot('completed')
        report=self.call('GET','/api/trips/'+self.trip['trip_id']+'/report')
        self.snapshots['report']={'fixture_only':True,'response':report}
        return report['report']


def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def record(output):
    with tempfile.TemporaryDirectory() as temp:
        clock=Clock()
        server=ThreadingHTTPServer(('127.0.0.1',0),partial(QuietHandler,directory=str(Path(temp))))
        server.store=Store(Path(temp)/'b4.sqlite3',clock_ms=clock)
        thread=threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        results=[]
        try:
            variants=[('correct-default','correct',{}),('correct-alternative','correct',dict(luggage_space='occupied',relocation='unavailable',seat_reason='intentional')),
                      ('incorrect','incorrect',{}),('missed','missed',{}),('critical-timeout','critical_timeout',{})]
            for name,kind,conditions in variants:
                demo=Demo(server,clock)
                began=clock.ms
                report=demo.run(kind,conditions)
                write(output/'http-exchanges'/f'{name}.json',dict(clock='injected_server_clock',player_id=demo.player,exchanges=demo.exchanges))
                for id,snapshot in demo.snapshots.items():write(output/'fixtures'/name/(id+'.json'),snapshot)
                results.append(dict(path=name,outcome=report['outcome'],scales=report['scales'],history_entries=len(report['history']),
                                    simulation_seconds=360,modeled_wall_seconds=(clock.ms-began)/1000))
            write(output/'results.json',results)
            paths=all_paths(server.store.b4_bundle)
            write(output/'paths.json',paths)
            lines=['# Проверенные пути Б4','', 'Все формулировки и оценки — демонстрационные черновики. Таблица перечисляет все доступные пути; серверные тесты исполняют каждый.','',
                   '| Сценарий / условие | Действия | Исход | Изменения лояльности | Δ безопасности | Объяснение |','|---|---|---|---|---:|---|']
            for p in paths:
                lines.append('| '+ ' | '.join([p['scenario_id']+' / '+str(p['conditions']),' → '.join(p['actions']),p['outcome'],str(p['effects']['loyalty_deltas']),str(p['effects']['safety_delta']),p['explanation']])+' |')
            lines+=['','## Просрочки','', '| Сценарий | Ожидание | Исход | Δ лояльности | Δ безопасности | Объяснение |','|---|---|---|---|---:|---|']
            for s in server.store.b4_bundle['scenarios'].values():
                for kind in ('reaction_timeout','decision_timeout','trip_timeout'):
                    if kind in s:
                        a=s[kind]
                        lines.append('| '+' | '.join([s['id'],kind,a['next'],str(a['effects']['loyalty_deltas']),str(a['effects'].get('safety_delta',0)),a['explanation']])+' |')
            (output/'paths.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
            print(json.dumps({'http_paths':len(results),'graph_paths':len(paths),'results':results},ensure_ascii=False,indent=2))
        finally:
            server.shutdown();server.server_close();thread.join(timeout=5)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path('docs/server/b4-local-check'))
    args=parser.parse_args()
    record(args.output)
