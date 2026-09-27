"""Data-driven full trip. Reuses B3 route math and event format, not its single dialog.

Every scenario/config is pinned by Store in scenario_json. All times are server
milliseconds; no client clock or score is accepted. Public API stays v1.
"""
from copy import deepcopy
import json
from pathlib import Path

try:
    from . import simulation as crew
except ImportError:
    import simulation as crew


def enabled(state):
    return state.get('simulation_mode') == 'full_b4'


def load(path):
    path = Path(path)
    cfg = json.loads(path.read_text(encoding='utf-8'))
    scenarios = [json.loads((path.parent / f).read_text(encoding='utf-8')) for f in cfg['scenario_files']]
    bundle = {'id': cfg['id'], 'version': cfg['version'], '_simulation_config': cfg,
              'scenarios': {s['id']: s for s in scenarios}}
    validate(bundle)
    return bundle


def validate(bundle):
    """Reject broken references/cycles/dead ends for every allowed condition set."""
    from itertools import product
    cfg = crew.config(bundle)
    assert len(cfg['incidents']) == 5 and len(cfg['staff']) == 3 and len(cfg['carriages']) == 2
    assert len({i['id'] for i in cfg['incidents']}) == 5
    points = {p['id']: p['carriage_id'] for p in cfg['route_points']}
    assert len(cfg['edge_seconds']) == len(points) - 1
    assert all(n > 0 for n in cfg['edge_seconds'])
    for i in cfg['incidents']:
        assert points[i['route_point_id']] == i['carriage_id']
        assert 0 <= i['appears_at'] < cfg['duration_seconds']
        assert i['reaction_seconds'] > 0
        if i['type'] != 'service':
            assert i['scenario_id'] in bundle['scenarios']
    for s in bundle['scenarios'].values():
        assert s['sources'] and s['verification_status'] and s['version']
        nodes = s['nodes']
        for n in nodes.values():
            actions = n.get('actions', [])
            assert len(actions) <= 3 and len({a['id'] for a in actions}) == len(actions)
            for a in actions + n.get('branches', []):
                assert a['next'] in nodes
            for a in actions:
                assert a['explanation'] and a['explanation_status'] == 'draft'
        for values in product(*s['condition_schema'].values()):
            conditions = dict(zip(s['condition_schema'], values))
            endings = set()
            def walk(id, ancestors):
                assert id not in ancestors, ('cycle', id)
                n = nodes[id]
                if 'outcome' in n:
                    assert n['recommendation'] and n['text']
                    endings.add(id)
                    return
                choices = [a for a in n.get('branches', n.get('actions', [])) if available(a, conditions)]
                assert choices, ('dead_end', s['id'], id, conditions)
                if 'branches' in n:
                    assert len(choices) == 1
                for a in choices:
                    walk(a['next'], ancestors | {id})
            walk(s['initial_node'], set())
            assert any(nodes[n]['successful'] for n in endings)
        for kind in ('reaction_timeout', 'trip_timeout'):
            assert s[kind]['next'] in nodes and s[kind]['explanation']
        for node_id, clock in s['critical_nodes'].items():
            assert node_id in nodes and clock['seconds'] > 0 and clock['next'] in nodes


def available(action, conditions):
    return all(conditions.get(k) == v for k, v in action['conditions'].items())


def context(item):
    return item['_scenario_state']


def content(bundle, item):
    return bundle['scenarios'][item['scenario_id']]


def enter(item, scenario, node_id):
    ctx = context(item)
    node = scenario['nodes'][node_id]
    while 'branches' in node:
        node_id = next(b['next'] for b in node['branches'] if available(b, ctx['conditions']))
        node = scenario['nodes'][node_id]
    timer = scenario['critical_nodes'].get(node_id)
    ctx.update(node_id=node_id, node_elapsed_ms=0,
               decision_ms=timer['seconds'] * 1000 if timer else None)
    return node


def initial(trip_id, bundle, conditions, now_ms):
    cfg = crew.config(bundle)
    state = dict(trip_id=trip_id, status='in_progress', state_version=1,
                 scenario_id=cfg['id'], scenario_version=cfg['version'], simulation_version=cfg['version'],
                 content_status='draft', verification_status='unverified_missing_dataset',
                 simulation_mode='full_b4', clock_mode='server_b4', created_at=crew.stamp(now_ms),
                 completed_at=None, outcome=None, conditions=conditions, facts={},
                 active_dialog_id=None, history=[], events=[], incidents=[],
                 _last_wall_ms=now_ms, _sim_ms=0,
                 scales={'loyalty': {}, 'overall_loyalty': None, 'safety': cfg['initial_safety']}, critical_marks=[])
    points = {p['id']: p['carriage_id'] for p in cfg['route_points']}
    state['staff'] = [{**s, 'carriage_id': points[s['route_point_id']], 'state': 'free', 'incident_id': None, 'route': None} for s in cfg['staff']]
    for data in cfg['incidents']:
        item = deepcopy(data)
        at = data['appears_at'] * 1000
        item.update(state='scheduled', resolution=None, assigned_staff_id=None,
                    _appeared_ms=at, _reaction_due_ms=at + data['reaction_seconds'] * 1000,
                    _arrived_ms=None, _service_due_ms=None)
        if data['type'] != 'service':
            s = content(bundle, item)
            item['_scenario_state'] = {'conditions': {k: conditions[k] for k in s['condition_schema']},
                                        'facts': deepcopy(s['initial_facts'])}
            enter(item, s, s['initial_node'])
        state['incidents'].append(item)
        for p in item['participant_ids']:
            state['scales']['loyalty'][p] = cfg['initial_loyalty']
    crew.aggregate(state)
    advance(state, bundle, now_ms)
    return state


def dialog_id(item):
    return item['id'] + '-dialog'


def finish(state, item, outcome):
    crew.finish_incident(state, item, outcome)
    if '_scenario_state' in item:
        context(item)['decision_ms'] = None
    if state['active_dialog_id'] == dialog_id(item):
        state['active_dialog_id'] = None


def apply(state, bundle, item, action, request_id, source='player'):
    ctx = context(item) if item['type'] != 'service' else None
    effects = action['effects']
    deltas = effects.get('loyalty_deltas', {p: effects.get('loyalty_delta', 0) for p in item['participant_ids']})
    for p, delta in deltas.items():
        assert p in item['participant_ids']
        state['scales']['loyalty'][p] += delta
    state['scales']['safety'] += effects.get('safety_delta', 0)
    for mark in effects.get('critical_marks', []):
        if mark not in state['critical_marks']:
            state['critical_marks'].append(mark)
    before = ctx['node_id'] if ctx else item['state']
    elapsed = ctx['node_elapsed_ms'] if ctx else 0
    scenario = content(bundle, item) if ctx else None
    if ctx:
        ctx['facts'].update(effects.get('facts', {}))
        state['facts'][item['id']] = deepcopy(ctx['facts'])
        node = enter(item, scenario, action['next'])
        if 'outcome' in node:
            finish(state, item, node['outcome'])
    else:
        finish(state, item, action['next'])
    state['history'].append(dict(request_id=request_id, action_id=action['id'], incident_id=item['id'],
        scenario_id=scenario['id'] if scenario else None, scenario_version=scenario['version'] if scenario else crew.config(bundle)['version'],
        conditions=deepcopy(ctx['conditions']) if ctx else {}, node_before=before,
        node_after=ctx['node_id'] if ctx else 'completed', selected_text=action['text'], effects=deepcopy(effects),
        explanation=action['explanation'], explanation_status='draft', content_status='draft',
        competency_evidence=deepcopy(action.get('competency_evidence', [])), source=source,
        simulation_time=crew.seconds(state['_sim_ms']), decided_at=crew.stamp(state['_last_wall_ms']),
        decision_time_seconds=crew.seconds(elapsed)))
    state['state_version'] += 1
    crew.aggregate(state)


def timeout(state, bundle, item, kind):
    s = content(bundle, item)
    action = deepcopy(s[kind])
    if kind == 'decision_timeout':
        action['next'] = s['critical_nodes'][context(item)['node_id']]['next']
    apply(state, bundle, item, action, 'auto:' + kind + ':' + item['id'], kind)


def service(state, bundle, item, missed=False):
    explanation = item['timeout_explanation' if missed else 'success_explanation']
    kind = 'reaction_timeout' if missed else 'service'
    apply(state, bundle, item, dict(id=kind, next='missed' if missed else 'served',
        effects=item['timeout' if missed else 'success'], text=explanation, explanation=explanation),
        'auto:' + kind + ':' + item['id'], kind)


def arrive(state, bundle, staff):
    item = crew.incident(state, staff['incident_id'])
    staff['route_point_id'] = staff['route']['point_ids'][-1]
    staff['route'] = None
    if item['state'] == 'completed':
        staff.update(state='free', incident_id=None)
    else:
        staff['state'] = 'serving'
        item.update(state='resolving', _arrived_ms=state['_sim_ms'])
        if item['type'] == 'service':
            item['_service_due_ms'] = state['_sim_ms'] + item['service_seconds'] * 1000
    crew.event(state, 'arrival', staff_id=staff['id'], incident_id=item['id'])
    crew.refresh_positions(state, bundle)


def end_trip(state, bundle):
    for item in state['incidents']:
        if item['state'] != 'completed':
            if item['type'] == 'service':
                service(state, bundle, item, missed=True)
            else:
                timeout(state, bundle, item, 'trip_timeout')
    for staff in state['staff']:
        staff.update(state='free', incident_id=None, route=None)
    success = all(i['resolution'] == 'served' if i['type'] == 'service'
                  else content(bundle, i)['nodes'][context(i)['node_id']]['successful'] for i in state['incidents'])
    state.update(status='completed', completed_at=crew.stamp(state['_last_wall_ms']), active_dialog_id=None,
                 outcome='successful' if success and not state['critical_marks'] else 'completed_with_issues')
    crew.event(state, 'trip_completed', outcome=state['outcome'])


def advance(state, bundle, now_ms):
    target = max(now_ms, state['_last_wall_ms'])
    while state['status'] != 'completed':
        paused = state['active_dialog_id'] is not None
        rate = 1 if paused else state.get('time_speed', 1)
        if rate == 0:
            state['_last_wall_ms'] = target
            return
        candidates = []
        for idx, item in enumerate(state['incidents']):
            # Other incidents, including their decision clocks, freeze during a dialog.
            if item['state'] == 'resolving' and item['type'] != 'service':
                ctx = context(item)
                if ctx['decision_ms'] is not None and (not paused or state['active_dialog_id'] == dialog_id(item)):
                    candidates.append((ctx['decision_ms'], 0, idx, 'decision', item))
            if not paused:
                if item['state'] == 'scheduled':
                    candidates.append((max(0, item['_appeared_ms'] - state['_sim_ms']), 1, idx, 'appear', item))
                if item['state'] in ('waiting', 'en_route'):
                    candidates.append((max(0, item['_reaction_due_ms'] - state['_sim_ms']), 2, idx, 'reaction', item))
                if item['_service_due_ms'] is not None:
                    candidates.append((max(0, item['_service_due_ms'] - state['_sim_ms']), 4, idx, 'service', item))
        if not paused:
            candidates.append((max(0, crew.config(bundle)['duration_seconds'] * 1000 - state['_sim_ms']), 5, 0, 'end', None))
            for idx, staff in enumerate(state['staff']):
                if staff['state'] == 'moving':
                    candidates.append((max(0, staff['route']['_arrives_ms'] - state['_sim_ms']), 3, idx, 'arrival', staff))
        selected = min(candidates, default=None, key=lambda c: c[:3])
        left = round((target - state['_last_wall_ms']) * rate)
        delta = min(left, selected[0]) if selected else left
        state['_last_wall_ms'] += delta / rate
        if not paused:
            state['_sim_ms'] += delta
        for item in state['incidents']:
            if item['state'] == 'resolving' and item['type'] != 'service' and (not paused or state['active_dialog_id'] == dialog_id(item)):
                ctx = context(item)
                ctx['node_elapsed_ms'] += delta
                if ctx['decision_ms'] is not None:
                    ctx['decision_ms'] -= delta
        crew.refresh_positions(state, bundle)
        if selected is None or selected[0] > left:
            break
        _, _, _, kind, obj = selected
        if kind == 'appear':
            obj['state'] = 'waiting'
            crew.event(state, 'incident_appeared', incident_id=obj['id'])
        elif kind == 'decision':
            timeout(state, bundle, obj, 'decision_timeout')
        elif kind == 'reaction':
            service(state, bundle, obj, True) if obj['type'] == 'service' else timeout(state, bundle, obj, 'reaction_timeout')
        elif kind == 'arrival':
            arrive(state, bundle, obj)
        elif kind == 'service':
            service(state, bundle, obj)
        else:
            end_trip(state, bundle)


def command(state, bundle, body, operation, fail):
    if operation == 'time':
        if type(body.get('speed')) is not int or body['speed'] not in (0, 1, 2, 4):
            fail(422, 'invalid_speed', 'Скорость: 0, 1, 2 или 4.')
        if state['active_dialog_id']:
            fail(409, 'dialog_open', 'Сначала завершите диалог.')
        state['time_speed'] = body['speed']
        crew.event(state, 'time_changed', speed=body['speed'])
        return
    item = crew.incident(state, body['incident_id'])
    if item is None:
        fail(422, 'invalid_incident', 'Обращение не относится к попытке.')
    if operation == 'assignments':
        if state['active_dialog_id']:
            fail(409, 'simulation_paused', 'Закройте диалог перед назначением.')
        staff = crew.employee(state, body['staff_id'])
        if staff is None:
            fail(422, 'invalid_staff', 'Сотрудник не относится к попытке.')
        if staff['state'] != 'free':
            fail(409, 'staff_busy', 'Сотрудник уже занят.')
        if item['state'] != 'waiting':
            fail(409, 'incident_unavailable', 'Обращение ещё не появилось, назначено или завершено.')
        staff.update(state='moving', incident_id=item['id'], route=crew.route(bundle, staff['route_point_id'], item['route_point_id'], state['_sim_ms']))
        item.update(state='en_route', assigned_staff_id=staff['id'])
        crew.event(state, 'assignment', incident_id=item['id'], staff_id=staff['id'])
        # A same-point assignment has no travel time, even during user pause.
        if staff['route']['_arrives_ms'] <= state['_sim_ms']:
            arrive(state, bundle, staff)
        else:
            advance(state, bundle, state['_last_wall_ms'])
        return
    if item['type'] == 'service' or item['state'] != 'resolving':
        fail(409, 'dialog_not_ready', 'Дождитесь прибытия к сложному обращению.')
    active = state['active_dialog_id']
    if active and active != dialog_id(item):
        fail(409, 'another_dialog_open', 'Сначала закройте текущий диалог.')
    if operation in ('open', 'close'):
        state['active_dialog_id'] = dialog_id(item) if operation == 'open' else None
        crew.event(state, 'dialog_' + operation, incident_id=item['id'])
        return
    if not active:
        fail(409, 'dialog_not_open', 'Сначала откройте диалог.')
    ctx, s = context(item), content(bundle, item)
    if body['node_id'] != ctx['node_id']:
        fail(422, 'invalid_node', 'Выбор относится к другому узлу.')
    action = next((a for a in s['nodes'][ctx['node_id']]['actions'] if a['id'] == body['action_id']), None)
    if action is None:
        fail(422, 'invalid_action', 'В текущем узле нет такого действия.')
    if not available(action, ctx['conditions']):
        fail(422, 'action_unavailable', action['unavailable_reason'])
    apply(state, bundle, item, action, body['request_id'])


def public(state, bundle):
    result = {k: deepcopy(v) for k, v in state.items() if not k.startswith('_')}
    cfg = crew.config(bundle)
    result.update(carriages=deepcopy(cfg['carriages']), server_time=crew.stamp(state['_last_wall_ms']),
                  simulation_time=crew.seconds(state['_sim_ms']), remaining_time=max(0, cfg['duration_seconds'] - crew.seconds(state['_sim_ms'])),
                  time_speed=state.get('time_speed', 1),
                  paused=bool(state['active_dialog_id']) or state.get('time_speed', 1) == 0,
                  pause_reason='dialog' if state['active_dialog_id'] else ('user' if state.get('time_speed', 1) == 0 else None),
                  balance_status=cfg['balance_status'], dialog=None, node_id='completed' if state['status'] == 'completed' else 'scheduled', assignment_options=[], incidents=[])
    upcoming = [i['_appeared_ms'] for i in state['incidents'] if i['state'] == 'scheduled']
    result['next_incident_time'] = crew.seconds(min(upcoming)) if upcoming else None
    result['scenario_versions'] = {k: s['version'] for k, s in bundle['scenarios'].items()}
    for item in state['incidents']:
        if item['state'] == 'scheduled':
            continue  # No new incident-state enum for existing clients.
        entry = {k: deepcopy(v) for k, v in item.items() if not k.startswith('_') and k not in ('success','timeout','reaction_seconds','service_seconds')}
        entry.update(appeared_at=crew.seconds(item['_appeared_ms']), reaction_deadline=crew.seconds(item['_reaction_due_ms']),
                     arrived_at=crew.seconds(item['_arrived_ms']),
                     reaction_time=crew.seconds(max(0,item['_reaction_due_ms']-state['_sim_ms'])) if item['state'] in ('waiting','en_route') else None,
                     service_remaining=crew.seconds(max(0,item['_service_due_ms']-state['_sim_ms'])) if item['_service_due_ms'] is not None else None)
        if item['type'] != 'service':
            ctx, s = context(item), content(bundle, item)
            entry.update(scenario_version=s['version'], content_status=s['content_status'], verification_status=s['verification_status'],
                         node_id=ctx['node_id'], conditions=deepcopy(ctx['conditions']), facts=deepcopy(ctx['facts']),
                         critical_decision_time=crew.seconds(ctx['decision_ms']) if item['state']=='resolving' else None)
            if item['state'] == 'completed':
                n = s['nodes'][ctx['node_id']]
                entry.update(summary=n['text'], recommendation=n['recommendation'], successful=n['successful'])
        result['incidents'].append(entry)
        if item['state'] == 'waiting' and not state['active_dialog_id']:
            for staff in state['staff']:
                if staff['state'] == 'free':
                    r = crew.route(bundle, staff['route_point_id'], item['route_point_id'], 0)
                    result['assignment_options'].append(dict(incident_id=item['id'], staff_id=staff['id'], route_point_ids=r['point_ids'], travel_seconds=crew.seconds(r['_arrives_ms'])))
    ready = [i for i in state['incidents'] if i['state'] == 'resolving' and i['type'] != 'service']
    selected = next((i for i in ready if dialog_id(i) == state['active_dialog_id']), ready[0] if ready else None)
    if selected:
        ctx, s = context(selected), content(bundle, selected)
        n = s['nodes'][ctx['node_id']]
        result['node_id'] = ctx['node_id']
        result['dialog'] = dict(id=dialog_id(selected), incident_id=selected['id'], scenario_id=s['id'], node_id=ctx['node_id'],
            text=n['text'], text_status=n['text_status'], is_open=bool(state['active_dialog_id']),
            critical_decision_time=crew.seconds(ctx['decision_ms']), options=[dict(id=a['id'],text=a['text'],text_status=a['text_status'],
                available=available(a,ctx['conditions']),unavailable_reason=None if available(a,ctx['conditions']) else a['unavailable_reason']) for a in n['actions']])
    # Route wire format is the established B3 shape.
    result['staff'] = []
    for staff in state['staff']:
        entry = deepcopy(staff)
        entry.update(arrival_remaining=None, position={'from':staff['route_point_id'],'to':staff['route_point_id'],'progress':1})
        if staff['route']:
            r = staff['route']
            entry['route'] = dict(point_ids=r['point_ids'],started_at=crew.seconds(r['_started_ms']),arrives_at=crew.seconds(r['_arrives_ms']),
                segments=[dict(**{'from':v['from'],'to':v['to']},starts_at=crew.seconds(v['_starts_ms']),ends_at=crew.seconds(v['_ends_ms'])) for v in r['segments']])
            entry['arrival_remaining'] = crew.seconds(max(0,r['_arrives_ms']-state['_sim_ms']))
            for v in r['segments']:
                if v['_starts_ms'] <= state['_sim_ms'] < v['_ends_ms']:
                    entry['position'] = {'from':v['from'],'to':v['to'],'progress':(state['_sim_ms']-v['_starts_ms'])/(v['_ends_ms']-v['_starts_ms'])}
        result['staff'].append(entry)
    return result


def report(state, bundle):
    if state['status'] != 'completed':
        return None
    view = public(state, bundle)
    result = {k:deepcopy(view[k]) for k in ('trip_id','scenario_id','scenario_version','scenario_versions','content_status','verification_status',
        'state_version','completed_at','outcome','facts','scales','critical_marks','history','events','completed_participant_ids','simulation_mode','simulation_version','incidents')}
    result.update(summary='Все пять обращений обработаны.' if state['outcome']=='successful' else 'Рейс завершён с нерешёнными или непроверенными обращениями.',
                  recommendation='Разберите сохранённые действия и объяснения по каждому обращению.',text_status='draft',
                  sources={k:deepcopy(s['sources']) for k,s in bundle['scenarios'].items()},
                  duration_seconds=crew.seconds(state['_sim_ms']))
    return result
