"""SQLite transactions own attempts, pinned content, history and idempotency results."""
import json
import re
import sqlite3
import time
from copy import deepcopy
from contextlib import closing
from pathlib import Path
from uuid import uuid4

try:
    from . import simulation, trip_b4, progress_b5
    from .scenario import initial, public_state, apply_action, available
except ImportError:
    import simulation, trip_b4, progress_b5
    from scenario import initial, public_state, apply_action, available

BASE = Path(__file__).resolve().parent
REQUEST_ID = re.compile(r'[A-Za-z0-9_-]{1,128}\Z')


def encode(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)


class APIError(Exception):
    def __init__(self, status, code, message, **details):
        self.status = status
        self.data = {'ok': False, 'api_version': 'v1', 'error': code, 'message': message, **details}
        super().__init__(message)


def fail(status, code, message, **details):
    raise APIError(status, code, message, **details)


class Store:
    def __init__(self, path, scenario_path=None, simulation_path=None, clock_ms=None):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.scenario = json.loads(Path(scenario_path or BASE / 'data/luggage-v1.json').read_text(encoding='utf-8'))
        self.clock_ms = clock_ms or (lambda: time.time_ns() // 1_000_000)
        self.simulation_config = json.loads(Path(simulation_path or BASE / "data/simulation-b3.json").read_text(encoding="utf-8"))
        self.b4_bundle = trip_b4.load(BASE / "data/trip-b4.json")
        self.validate_scenario()
        with closing(self.connect()) as db:
            db.execute('PRAGMA journal_mode=WAL')
            db.execute('BEGIN IMMEDIATE')
            try:
                version = db.execute('PRAGMA user_version').fetchone()[0]
                if version == 0:
                    for statement in (BASE / 'migrations/001_initial.sql').read_text().split(';'):
                        if statement.strip():
                            db.execute(statement)
                    version = 1
                if version == 1:
                    for statement in (BASE / 'migrations/002_progress.sql').read_text().split(';'):
                        if statement.strip():
                            db.execute(statement)
                elif version != 2:
                    raise RuntimeError(f'Unsupported database version: {version}')
                # Backfill only full B4 attempts, in completion order, atomically.
                for row in db.execute('SELECT * FROM trips ORDER BY json_extract(state_json, "$.completed_at"), trip_id').fetchall():
                    state = json.loads(row['state_json'])
                    if trip_b4.enabled(state):
                        bundle = json.loads(row['scenario_json'])
                        if '_progress_config' not in bundle:
                            bundle['_progress_config'] = deepcopy(progress_b5.DEFAULT_RULES)
                            db.execute('UPDATE trips SET scenario_json=? WHERE trip_id=?', (encode(bundle), row['trip_id']))
                        if state['status'] == 'completed':
                            self.settle(db, state, bundle)
                db.commit()
            except Exception:
                db.rollback()
                raise

    def validate_scenario(self):
        nodes = self.scenario['nodes']
        assert self.scenario['initial_node'] in nodes
        for node in nodes.values():
            actions = node.get('actions', [])
            assert len(actions) <= 3
            assert len({a['id'] for a in actions}) == len(actions)
            for item in actions + node.get('branches', []):
                assert item['next'] in nodes

    def connect(self):
        db = sqlite3.connect(str(self.path), timeout=10, isolation_level=None)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        db.execute('PRAGMA synchronous=FULL')
        return db

    def read_trip(self, db, player_id, trip_id):
        row = db.execute('SELECT * FROM trips WHERE trip_id=? AND player_id=?', (trip_id, player_id)).fetchone()
        if row is None:
            fail(404, 'trip_not_found', 'Попытка не найдена у этого демо-игрока.')
        return row, json.loads(row['state_json']), json.loads(row['scenario_json'])

    def engine(self, state):
        return trip_b4 if trip_b4.enabled(state) else simulation

    def view(self, state, scenario):
        if trip_b4.enabled(state):
            return trip_b4.public(state, scenario)
        return simulation.public(state, scenario) if simulation.enabled(state) else public_state(state, scenario)

    def save_simulation(self, db, state, scenario):
        if trip_b4.enabled(state) and state['status'] == 'completed':
            self.settle(db, state, scenario)
            db.execute('UPDATE trips SET state_json=? WHERE trip_id=?', (encode(state), state['trip_id']))
            return
        report = self.engine(state).report(state, scenario)
        db.execute('UPDATE trips SET state_json=?, report_json=? WHERE trip_id=?',
                   (encode(state), encode(report) if report else None, state['trip_id']))

    def sync(self, db, player_id, trip_id):
        row, state, scenario = self.read_trip(db, player_id, trip_id)
        if (simulation.enabled(state) or trip_b4.enabled(state)) and state['status'] != 'completed':
            self.engine(state).advance(state, scenario, self.clock_ms())
            self.save_simulation(db, state, scenario)
            row = db.execute('SELECT * FROM trips WHERE trip_id=?', (trip_id,)).fetchone()
        return row, state, scenario

    def get(self, player_id, trip_id=None, report=False):
        with closing(self.connect()) as db:
            db.execute('BEGIN IMMEDIATE')
            try:
                if trip_id is None:
                    player = db.execute('SELECT current_trip_id FROM players WHERE player_id=?', (player_id,)).fetchone()
                    if player is None or not player['current_trip_id']:
                        fail(404, 'no_current_trip', 'У демо-игрока пока нет попытки.')
                    trip_id = player['current_trip_id']
                row, state, scenario = self.sync(db, player_id, trip_id)
                db.commit()
                if report:
                    if row['report_json'] is None:
                        fail(409, 'report_not_ready', 'Завершите сценарий перед получением разбора.', current_state_version=state['state_version'])
                    return {'ok': True, 'api_version': 'v1', 'report': json.loads(row['report_json'])}
                return {'ok': True, 'api_version': 'v1', 'trip': self.view(state, scenario)}
            except Exception:
                db.rollback()
                raise

    def mutate(self, player_id, path, body, trip_id=None):
        legacy = trip_id is None and body == {}
        request_id = body.get('request_id')
        if legacy:
            request_id = 'legacy-' + uuid4().hex
        elif not isinstance(request_id, str) or not REQUEST_ID.fullmatch(request_id):
            fail(400, 'invalid_request_id', 'Нужен request_id: 1–128 латинских букв, цифр, _ или -.')
        fingerprint = encode({'path': path, 'body': body})
        with closing(self.connect()) as db:
            db.execute('BEGIN IMMEDIATE')
            command_started = False
            try:
                previous = db.execute('SELECT * FROM requests WHERE player_id=? AND request_id=?', (player_id, request_id)).fetchone()
                if previous:
                    if previous['fingerprint'] != fingerprint:
                        fail(409, 'request_id_conflict', 'request_id уже использован с другим содержимым или маршрутом.')
                    db.commit()
                    return json.loads(previous['response_json'])
                # Time is server-owned. Commit due events even when the command is
                # rejected; command changes remain isolated behind a savepoint.
                if trip_id is not None:
                    prepared = self.sync(db, player_id, trip_id)
                else:
                    player = db.execute('SELECT current_trip_id FROM players WHERE player_id=?', (player_id,)).fetchone()
                    if player and player['current_trip_id']:
                        self.sync(db, player_id, player['current_trip_id'])
                db.execute('SAVEPOINT command')
                command_started = True
                if trip_id is None:
                    response = self.start(db, player_id, body)
                else:
                    response = self.act(db, player_id, trip_id, body, path, prepared)
                db.execute('INSERT INTO requests VALUES (?,?,?,?)', (player_id, request_id, fingerprint, encode(response)))
                db.commit()
                return response
            except APIError:
                if command_started:
                    db.execute('ROLLBACK TO command')
                    db.commit()
                else:
                    db.rollback()
                raise
            except Exception:
                db.rollback()
                raise

    def start(self, db, player_id, body):
        if set(body) - {'request_id', 'luggage_space', 'new_attempt', 'simulation_mode', 'relocation', 'seat_reason'}:
            fail(400, 'invalid_fields', 'Неизвестные поля старта.')
        if 'new_attempt' in body and type(body['new_attempt']) is not bool:
            fail(400, 'invalid_fields', 'new_attempt должен быть boolean.')
        mode = body.get('simulation_mode', 'untimed_b1')
        if mode not in ('untimed_b1', 'crew_b3', 'full_b4'):
            fail(400, 'invalid_fields', 'Неизвестный simulation_mode.')
        condition = body.get('luggage_space', self.scenario['default_luggage_space'])
        if condition not in self.scenario['allowed_luggage_space']:
            fail(400, 'invalid_condition', 'luggage_space должен быть free или occupied.')
        b4_conditions = {**self.b4_bundle['_simulation_config']['default_conditions'], 'luggage_space': condition}
        for key in ('relocation', 'seat_reason'):
            if key in body:
                if mode != 'full_b4':
                    fail(400, 'invalid_fields', 'Дополнительные условия доступны только в full_b4.')
                allowed = next(s['condition_schema'][key] for s in self.b4_bundle['scenarios'].values() if key in s['condition_schema'])
                if body[key] not in allowed:
                    fail(400, 'invalid_condition', 'Недопустимое условие: ' + key)
                b4_conditions[key] = body[key]
        player = db.execute('SELECT * FROM players WHERE player_id=?', (player_id,)).fetchone()
        resumed = False
        if player and player['current_trip_id']:
            _, state, scenario = self.read_trip(db, player_id, player['current_trip_id'])
            if body.get('new_attempt', False):
                if state['status'] != 'completed':
                    fail(409, 'active_trip_exists', 'Сначала завершите текущую попытку.', trip_id=state['trip_id'])
            else:
                if 'simulation_mode' in body and mode != state.get('simulation_mode', 'untimed_b1'):
                    fail(409, 'mode_conflict', 'Режим сохранённой попытки отличается.', trip_id=state['trip_id'])
                if 'luggage_space' in body and condition != state['conditions']['luggage_space']:
                    fail(409, 'condition_conflict', 'Условие сохранённой попытки отличается. Восстановите её через GET.', trip_id=state['trip_id'])
                for key in ('relocation', 'seat_reason'):
                    if key in body and body[key] != state['conditions'].get(key):
                        fail(409, 'condition_conflict', 'Условие сохранённой попытки отличается: ' + key)
                resumed = True
        if not resumed:
            db.execute('INSERT OR IGNORE INTO players(player_id) VALUES (?)', (player_id,))
            trip_id = uuid4().hex.upper()
            scenario = deepcopy(self.scenario)
            if mode == 'crew_b3':
                scenario['_simulation_config'] = deepcopy(self.simulation_config)
                scenario['nodes'].update(deepcopy(self.simulation_config['timeout_nodes']))
            if mode == 'full_b4':
                scenario = deepcopy(self.b4_bundle)
                scenario['_progress_config'] = deepcopy(progress_b5.DEFAULT_RULES)
                state = trip_b4.initial(trip_id, scenario, b4_conditions, self.clock_ms())
            else:
                state = initial(trip_id, condition, scenario)
            if mode == 'crew_b3':
                simulation.initialize(state, scenario, self.clock_ms())
            db.execute('INSERT INTO trips VALUES (?,?,?,?,NULL)', (trip_id, player_id, encode(state), encode(scenario)))
            db.execute('UPDATE players SET current_trip_id=? WHERE player_id=?', (trip_id, player_id))
        return {'ok': True, 'api_version': 'v1', 'status': 'started', 'trip_id': state['trip_id'],
                'player_id': player_id, 'resumed': resumed, 'trip': self.view(state, scenario)}

    def act(self, db, player_id, trip_id, body, path, prepared):
        row, state, scenario = prepared
        operation = path.rsplit('/', 1)[-1]
        if operation == 'complete':
            if set(body) != {'request_id'}:
                fail(400, 'invalid_fields', 'Для подтверждения нужен только request_id.')
            if state['status'] != 'completed':
                fail(409, 'trip_not_completed', 'Дождитесь серверного завершения рейса.')
            return {'ok': True, 'api_version': 'v1', 'report': json.loads(row['report_json'])}
        fields = {'actions': {'incident_id', 'node_id', 'action_id'},
                  'assignments': {'incident_id', 'staff_id'},
                  'open': {'incident_id'}, 'close': {'incident_id'}, 'time': {'speed'}}
        if operation not in fields:
            fail(404, 'not_found', 'Маршрут не найден.')
        required = {'request_id', 'expected_state_version'} | fields[operation]
        if set(body) != required or any(not isinstance(body.get(k), str) for k in fields[operation] if k != 'speed'):
            fail(400, 'invalid_fields', 'Неверные поля команды.')
        if type(body['expected_state_version']) is not int or body['expected_state_version'] < 1:
            fail(400, 'invalid_state_version', 'expected_state_version должен быть целым числом от 1.')
        if body['expected_state_version'] != state['state_version']:
            fail(409, 'state_version_conflict', 'Состояние изменилось. Получите его через GET.', current_state_version=state['state_version'])
        if state['status'] == 'completed':
            fail(409, 'trip_completed', 'Попытка завершена; доступен сохранённый разбор.')
        if trip_b4.enabled(state):
            trip_b4.command(state, scenario, body, operation, fail)
            self.save_simulation(db, state, scenario)
            return {'ok': True, 'api_version': 'v1', 'trip': self.view(state, scenario),
                    'report_available': state['status'] == 'completed'}
        if operation == 'time':
            fail(409, 'simulation_required', 'Управление временем доступно в новом рейсе.')
        if simulation.enabled(state):
            return self.act_simulation(db, state, scenario, body, operation)
        if operation != 'actions':
            fail(409, 'simulation_required', 'Начните новую попытку в режиме crew_b3.')
        if body['incident_id'] != scenario['incident']['id']:
            fail(422, 'invalid_incident', 'Обращение не относится к попытке.')
        if body['node_id'] != state['node_id']:
            fail(422, 'invalid_node', 'Выбор относится к другому узлу.')
        action = next((a for a in scenario['nodes'][state['node_id']]['actions'] if a['id'] == body['action_id']), None)
        if action is None:
            fail(422, 'invalid_action', 'В текущем узле нет такого действия.')
        if not available(action, state):
            fail(422, 'action_unavailable', action['unavailable_reason'])
        report = apply_action(state, scenario, action, body['request_id'])
        db.execute('UPDATE trips SET state_json=?, report_json=? WHERE trip_id=?',
                   (encode(state), encode(report) if report else None, trip_id))
        return {'ok': True, 'api_version': 'v1', 'trip': self.view(state, scenario), 'report_available': report is not None}

    def act_simulation(self, db, state, scenario, body, operation):
        item = simulation.incident(state, body['incident_id'])
        if item is None:
            fail(422, 'invalid_incident', 'Обращение не относится к попытке.')
        if operation == 'assignments':
            if state['active_dialog_id']:
                fail(409, 'simulation_paused', 'Закройте диалог перед назначением.')
            staff = simulation.employee(state, body['staff_id'])
            if staff is None:
                fail(422, 'invalid_staff', 'Сотрудник не относится к попытке.')
            if staff['state'] != 'free':
                fail(409, 'staff_busy', 'Сотрудник уже занят.')
            if item['state'] != 'waiting':
                fail(409, 'incident_unavailable', 'Обращение уже назначено или завершено.')
            simulation.assign(state, scenario, item, staff)
        else:
            if item['type'] == 'service' or item['state'] != 'resolving':
                fail(409, 'dialog_not_ready', 'Дождитесь прибытия сотрудника к сложному обращению.')
            if operation in ('open', 'close'):
                simulation.set_dialog(state, item, operation == 'open')
            else:
                if not state['active_dialog_id']:
                    fail(409, 'dialog_not_open', 'Сначала откройте диалог.')
                if body['node_id'] != state['node_id']:
                    fail(422, 'invalid_node', 'Выбор относится к другому узлу.')
                action = next((a for a in scenario['nodes'][state['node_id']]['actions'] if a['id'] == body['action_id']), None)
                if action is None:
                    fail(422, 'invalid_action', 'В текущем узле нет такого действия.')
                if not available(action, state):
                    fail(422, 'action_unavailable', action['unavailable_reason'])
                simulation.choose(state, scenario, action, body['request_id'])
        self.save_simulation(db, state, scenario)
        return {'ok': True, 'api_version': 'v1', 'trip': self.view(state, scenario),
                'report_available': state['status'] == 'completed'}

    def ensure_profile(self, db, player_id):
        db.execute('INSERT OR IGNORE INTO players(player_id) VALUES (?)', (player_id,))
        org = progress_b5.DEFAULT_RULES['default_organization']
        db.execute('INSERT OR IGNORE INTO profiles VALUES (?,?,?,?,?,?)',
                   (player_id, 'Учебный участник ' + player_id[:8], 0, org['crew_id'], org['depot_id'], org['company_id']))

    def total_points(self, db, player_id):
        return db.execute('SELECT COALESCE(SUM(points),0) FROM best_results WHERE player_id=?', (player_id,)).fetchone()[0]

    def settle(self, db, state, bundle):
        """Called inside the same IMMEDIATE transaction as completion/state update."""
        tid = state['trip_id']
        if db.execute('SELECT 1 FROM settlements WHERE trip_id=?', (tid,)).fetchone():
            return
        player_id = db.execute('SELECT player_id FROM trips WHERE trip_id=?', (tid,)).fetchone()[0]
        self.ensure_profile(db, player_id)
        report = progress_b5.report(state, bundle)
        previous_total = self.total_points(db, player_id)
        awarded = 0
        for score in report['scenario_scores']:
            key = (player_id, score['scenario_id'], score['scenario_version'])
            previous = db.execute('SELECT points FROM best_results WHERE player_id=? AND scenario_id=? AND scenario_version=?', key).fetchone()
            old = previous['points'] if previous else 0
            gain = max(0, score['points'] - old)
            score.update(previous_best=old, awarded=gain)
            awarded += gain
            if previous is None or gain:
                db.execute('INSERT INTO best_results VALUES (?,?,?,?,?,?) ON CONFLICT(player_id,scenario_id,scenario_version) DO UPDATE SET points=excluded.points,competencies_json=excluded.competencies_json,trip_id=excluded.trip_id',
                           (*key, score['points'], encode(score['competencies']), tid))
        unlocked_achievements = []
        for aid in report['eligible_achievements']:
            inserted = db.execute('INSERT OR IGNORE INTO achievements VALUES (?,?,?,?)',
                                  (player_id, aid, tid, state['completed_at'])).rowcount
            if inserted:
                unlocked_achievements.append(aid)
        unlocks, notification_ids = [], []
        if db.execute('INSERT OR IGNORE INTO content_unlocks VALUES (?,?,?)', (player_id, 'carriage-3', tid)).rowcount:
            unlocks.append('carriage-3')
            notification = dict(id='carriage-3', type='carriage_unlocked', carriage_id='carriage-3',
                                title='Открыт вагон № 3', message='Вагон открыт как будущий контент. Новый рейс пока недоступен; текущий можно повторить.',
                                content_status='future_content', created_at=state['completed_at'], trip_id=tid)
            db.execute('INSERT INTO notifications VALUES (?,?,?)', (player_id, notification['id'], encode(notification)))
            notification_ids.append(notification['id'])
        report.update(points=dict(earned=sum(s['points'] for s in report['scenario_scores']), awarded=awarded,
                                  previous_total=previous_total, total_after=previous_total+awarded),
                      achievements_unlocked=unlocked_achievements, unlocks=unlocks, notification_ids=notification_ids)
        db.execute('UPDATE trips SET report_json=? WHERE trip_id=?', (encode(report), tid))
        db.execute('INSERT INTO settlements VALUES (?,?,?)', (tid, player_id, awarded))

    def progress(self, player_id, operation='profile', scope='crew', page=1, page_size=10):
        if operation not in ('profile', 'leaderboard', 'notifications') or scope not in ('crew','depot','company') or type(page) is not int or type(page_size) is not int or not 1 <= page <= 1000000 or not 1 <= page_size <= 50:
            fail(400, 'invalid_query', 'Некорректные параметры страницы или фильтра.')
        with closing(self.connect()) as db:
            db.execute('BEGIN IMMEDIATE')
            try:
                self.ensure_profile(db, player_id)
                current = db.execute('SELECT current_trip_id FROM players WHERE player_id=?', (player_id,)).fetchone()[0]
                if current:
                    self.sync(db, player_id, current)
                profile = dict(db.execute('SELECT * FROM profiles WHERE player_id=?', (player_id,)).fetchone())
                organization = {k:profile[k] for k in ('crew_id','depot_id','company_id')}
                if operation == 'profile':
                    best = [dict(r) for r in db.execute('SELECT scenario_id,scenario_version,points,competencies_json,trip_id FROM best_results WHERE player_id=? ORDER BY scenario_id,scenario_version', (player_id,))]
                    totals = dict.fromkeys(progress_b5.DEFAULT_RULES['competencies'],0)
                    for b in best:
                        b['competencies'] = json.loads(b.pop('competencies_json'))
                        for k,v in b['competencies'].items():
                            totals[k] += v
                    achievements = []
                    for aid,name in progress_b5.DEFAULT_RULES['achievements'].items():
                        a = db.execute('SELECT earned_at,trip_id FROM achievements WHERE player_id=? AND achievement_id=?',(player_id,aid)).fetchone()
                        achievements.append(dict(id=aid,name=name,earned=a is not None,earned_at=a['earned_at'] if a else None,trip_id=a['trip_id'] if a else None))
                    content = []
                    for i in range(1,4):
                        unlocked = i < 3 or bool(db.execute('SELECT 1 FROM content_unlocks WHERE player_id=? AND content_id=?',(player_id,'carriage-'+str(i))).fetchone())
                        content.append(dict(id='carriage-'+str(i),name='Вагон № '+str(i),unlocked=unlocked,playable=i<3,status='playable' if i<3 else 'future_content' if unlocked else 'locked'))
                    reports = [r[0] for r in db.execute('SELECT trips.trip_id FROM trips JOIN settlements USING(trip_id) WHERE trips.player_id=? ORDER BY json_extract(report_json,"$.completed_at") DESC,trips.trip_id',(player_id,))]
                    data = dict(profile=dict(player_id=player_id,display_name=profile['display_name'],is_demo=bool(profile['is_demo']),organization=organization,
                                total_points=sum(totals.values()),completed_trips=len(reports),best_results=best,report_ids=reports,
                                competencies=[dict(id=k,name=n,points=totals[k]) for k,n in progress_b5.DEFAULT_RULES['competencies'].items()],
                                achievements=achievements,content=content))
                elif operation == 'notifications':
                    total = db.execute('SELECT COUNT(*) FROM notifications WHERE player_id=?',(player_id,)).fetchone()[0]
                    rows = db.execute('SELECT payload_json FROM notifications WHERE player_id=? ORDER BY notification_id LIMIT ? OFFSET ?', (player_id,page_size,(page-1)*page_size))
                    data = dict(page=page,page_size=page_size,total=total,total_pages=(total+page_size-1)//page_size,notifications=[json.loads(r[0]) for r in rows])
                else:
                    # scope column is selected from the validated fixed enumeration.
                    column = scope + '_id'
                    scope_id = profile[column]
                    query = f'FROM profiles p WHERE p.{column}=? AND EXISTS(SELECT 1 FROM settlements s WHERE s.player_id=p.player_id)'
                    total = db.execute('SELECT COUNT(*) '+query,(scope_id,)).fetchone()[0]
                    rows = db.execute('SELECT p.*, (SELECT COALESCE(SUM(b.points),0) FROM best_results b WHERE b.player_id=p.player_id) AS total_points '+query+' ORDER BY total_points DESC,p.player_id ASC LIMIT ? OFFSET ?', (scope_id,page_size,(page-1)*page_size))
                    entries = [dict(rank=(page-1)*page_size+idx+1,display_name=r['display_name'],total_points=r['total_points'],is_demo=bool(r['is_demo']),is_self=r['player_id']==player_id,
                                    organization={k:r[k] for k in organization}) for idx,r in enumerate(rows)]
                    data = dict(scope=scope,scope_id=scope_id,page=page,page_size=page_size,total=total,total_pages=(total+page_size-1)//page_size,entries=entries)
                db.commit()
                return dict(ok=True,api_version='v1',**data)
            except Exception:
                db.rollback()
                raise
