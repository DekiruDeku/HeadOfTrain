"""B3 authoritative discrete-event clock. Integer milliseconds, no client elapsed time.

All calls run inside Store's SQLite write transaction. Configuration is pinned in
scenario_json. Automatic events are processed in chronological order, including
unpausing partway through a long offline interval.
"""
from copy import deepcopy
from datetime import datetime, timezone

try:
    from . import scenario as luggage
except ImportError:
    import scenario as luggage


def stamp(milliseconds):
    return datetime.fromtimestamp(milliseconds / 1000, timezone.utc).isoformat()


def seconds(milliseconds):
    return None if milliseconds is None else milliseconds / 1000


def enabled(state):
    return state.get('simulation_mode') == 'crew_b3'


def config(scenario):
    return scenario['_simulation_config']


def initialize(state, scenario, now_ms):
    cfg = config(scenario)
    state.update(simulation_mode='crew_b3', simulation_version=cfg['version'],
                 clock_mode='server_b3', active_dialog_id=None, events=[],
                 _last_wall_ms=now_ms, _sim_ms=0, _decision_ms=None,
                 _node_elapsed_ms=0, _node_duration_ms=None,
                 created_at=stamp(now_ms), node_entered_at=stamp(now_ms))
    points = {p['id']: p['carriage_id'] for p in cfg['route_points']}
    state['staff'] = [{**s, 'carriage_id': points[s['route_point_id']],
                       'state': 'free', 'incident_id': None, 'route': None}
                      for s in cfg['staff']]
    state['incidents'] = []
    for item in cfg['incidents']:
        base = scenario['incident'] if item['id'] == scenario['incident']['id'] else {}
        state['incidents'].append({**base, **deepcopy(item), 'state': 'waiting',
                                  'resolution': None, 'assigned_staff_id': None,
                                  '_appeared_ms': 0, '_reaction_due_ms': item['reaction_seconds'] * 1000,
                                  '_arrived_ms': None, '_service_due_ms': None})
        for participant in item['participant_ids']:
            state['scales']['loyalty'].setdefault(participant, cfg['initial_loyalty'])
    aggregate(state)


def incident(state, incident_id):
    return next((i for i in state['incidents'] if i['id'] == incident_id), None)


def employee(state, staff_id):
    return next((s for s in state['staff'] if s['id'] == staff_id), None)


def main_incident(state, scenario):
    return incident(state, scenario['incident']['id'])


def route(scenario, origin, destination, started_ms):
    cfg = config(scenario)
    ids = [p['id'] for p in cfg['route_points']]
    a, b = ids.index(origin), ids.index(destination)
    indices = list(range(a, b + (1 if b >= a else -1), 1 if b >= a else -1))
    segments, end = [], started_ms
    for x, y in zip(indices, indices[1:]):
        duration = cfg['edge_seconds'][min(x, y)] * 1000
        segments.append({'from': ids[x], 'to': ids[y], '_starts_ms': end, '_ends_ms': end + duration})
        end += duration
    return {'point_ids': [ids[n] for n in indices], '_started_ms': started_ms,
            '_arrives_ms': end, 'segments': segments}


def refresh_positions(state, scenario):
    carriages = {p['id']: p['carriage_id'] for p in config(scenario)['route_points']}
    for staff in state['staff']:
        if staff['route']:
            for segment in staff['route']['segments']:
                if segment['_ends_ms'] <= state['_sim_ms']:
                    staff['route_point_id'] = segment['to']
        staff['carriage_id'] = carriages[staff['route_point_id']]


def event(state, kind, **fields):
    state['state_version'] += 1
    state['events'].append({'id': len(state['events']) + 1, 'type': kind,
                            'simulation_time': seconds(state['_sim_ms']),
                            'at': stamp(state['_last_wall_ms']), **fields})


def set_node_clock(state, scenario):
    node = config(scenario)['critical_nodes'].get(state['node_id'])
    state['_decision_ms'] = node['seconds'] * 1000 if node else None
    state['_node_duration_ms'] = state['_decision_ms']
    state['_node_elapsed_ms'] = 0
    state['node_entered_at'] = stamp(state['_last_wall_ms'])


def aggregate(state):
    participants = sorted({p for i in state['incidents'] if i['state'] == 'completed' for p in i['participant_ids']})
    state['completed_participant_ids'] = participants
    state['scales']['overall_loyalty'] = (sum(state['scales']['loyalty'][p] for p in participants) / len(participants)
                                         if participants else None)


def finish_incident(state, item, outcome):
    item.update(state='completed', resolution=outcome, _service_due_ms=None)
    staff = employee(state, item['assigned_staff_id'])
    # A late employee finishes the recorded journey, without servicing a closed request.
    if staff and staff['state'] != 'moving':
        staff.update(state='free', incident_id=None, route=None)
    aggregate(state)


def finish_trip(state):
    if all(i['state'] == 'completed' for i in state['incidents']) and all(s['state'] == 'free' for s in state['staff']):
        state['status'] = 'completed'
        state['completed_at'] = stamp(state['_last_wall_ms'])
        state['active_dialog_id'] = None


def choose(state, scenario, action, request_id, source='player'):
    elapsed = state['_node_elapsed_ms']
    luggage.apply_action(state, scenario, action, request_id)
    state['node_entered_at'] = stamp(state['_last_wall_ms'])
    # B1 stamps real time. B3 timestamps the exact event boundary instead.
    state['history'][-1].update(source=source, simulation_time=seconds(state['_sim_ms']),
                                decided_at=stamp(state['_last_wall_ms']), decision_time_seconds=seconds(elapsed))
    if state['status'] == 'completed':
        finish_incident(state, main_incident(state, scenario), state['outcome'])
        state.update(status='in_progress', completed_at=None, active_dialog_id=None)
        state['_decision_ms'] = None
    else:
        set_node_clock(state, scenario)
    aggregate(state)
    finish_trip(state)


def timeout_action(state, scenario, kind):
    cfg = config(scenario)
    data = cfg[kind]
    target = (cfg['critical_nodes'][state['node_id']]['next'] if kind == 'decision_timeout' else data['next'])
    action = {'id': kind, 'next': target, 'effects': data['effects'], 'text': data['text'],
              'explanation': data['text'], 'explanation_status': 'draft'}
    choose(state, scenario, action, 'auto:' + kind + ':' + scenario['incident']['id'], kind)


def complete_service(state, scenario, item, missed=False):
    effects = item['timeout'] if missed else item['success']
    for participant in item['participant_ids']:
        state['scales']['loyalty'][participant] += effects.get('loyalty_delta', 0)
    source = 'reaction_timeout' if missed else 'service'
    text = config(scenario)['service_timeout_text' if missed else 'service_text']
    state['history'].append({'request_id': 'auto:' + source + ':' + item['id'],
                             'action_id': source, 'incident_id': item['id'],
                             'node_before': item['state'], 'node_after': 'completed',
                             'selected_text': text, 'effects': deepcopy(effects),
                             'explanation': text, 'explanation_status': 'draft',
                             'decided_at': stamp(state['_last_wall_ms']), 'decision_time_seconds': 0,
                             'source': source, 'simulation_time': seconds(state['_sim_ms'])})
    state['state_version'] += 1
    finish_incident(state, item, 'missed' if missed else 'served')
    finish_trip(state)


def arrive(state, scenario, staff):
    item = incident(state, staff['incident_id'])
    staff['route_point_id'] = staff['route']['point_ids'][-1]
    staff['route'] = None
    if item['state'] == 'completed':
        staff.update(state='free', incident_id=None)
    else:
        staff['state'] = 'serving'
        item.update(state='resolving', _arrived_ms=state['_sim_ms'])
        if item['type'] == 'service':
            item['_service_due_ms'] = state['_sim_ms'] + item['service_seconds'] * 1000
        else:
            set_node_clock(state, scenario)
    event(state, 'arrival', staff_id=staff['id'], incident_id=item['id'])
    refresh_positions(state, scenario)
    finish_trip(state)


def advance(state, scenario, now_ms):
    """Consume elapsed wall time through event boundaries, independent of polling."""
    target = max(state['_last_wall_ms'], now_ms)
    while state['status'] != 'completed':
        paused = state['active_dialog_id'] is not None
        # (delay, priority, stable ordinal, kind, object). Deadline wins arrival ties.
        candidates = []
        if state['_decision_ms'] is not None:
            candidates.append((state['_decision_ms'], 0, 0, 'decision', None))
        if not paused:
            sim = state['_sim_ms']
            for idx, item in enumerate(state['incidents']):
                if item['state'] in ('waiting', 'en_route'):
                    candidates.append((max(0, item['_reaction_due_ms'] - sim), 1, idx, 'reaction', item))
                if item['_service_due_ms'] is not None:
                    candidates.append((max(0, item['_service_due_ms'] - sim), 3, idx, 'service', item))
            for idx, staff in enumerate(state['staff']):
                if staff['state'] == 'moving':
                    candidates.append((max(0, staff['route']['_arrives_ms'] - sim), 2, idx, 'arrival', staff))
        selected = min(candidates, default=None, key=lambda c: c[:3])
        left = target - state['_last_wall_ms']
        delta = min(left, selected[0]) if selected else left
        state['_last_wall_ms'] += delta
        if not paused:
            state['_sim_ms'] += delta
        if main_incident(state, scenario)['state'] == 'resolving':
            state['_node_elapsed_ms'] += delta
        if state['_decision_ms'] is not None:
            state['_decision_ms'] -= delta
        refresh_positions(state, scenario)
        if selected is None or selected[0] > left:
            break
        _, _, _, kind, obj = selected
        if kind == 'decision':
            timeout_action(state, scenario, 'decision_timeout')
        elif kind == 'reaction':
            if obj['type'] == 'service':
                complete_service(state, scenario, obj, missed=True)
            else:
                timeout_action(state, scenario, 'reaction_timeout')
        elif kind == 'arrival':
            arrive(state, scenario, obj)
        else:
            complete_service(state, scenario, obj)
    # Completed attempts are immutable, including their clock snapshot.


def assign(state, scenario, item, staff):
    staff.update(state='moving', incident_id=item['id'],
                 route=route(scenario, staff['route_point_id'], item['route_point_id'], state['_sim_ms']))
    item.update(state='en_route', assigned_staff_id=staff['id'])
    event(state, 'assignment', incident_id=item['id'], staff_id=staff['id'])
    # Same-point assignments arrive immediately and stop reaction immediately.
    advance(state, scenario, state['_last_wall_ms'])


def set_dialog(state, item, is_open):
    state['active_dialog_id'] = 'luggage-dialog' if is_open else None
    event(state, 'dialog_open' if is_open else 'dialog_close', incident_id=item['id'])


def public(state, scenario):
    result = luggage.public_state(state, scenario)
    for key in list(result):
        if key.startswith('_'):
            del result[key]
    result.update(server_time=stamp(state['_last_wall_ms']),
                  active_dialog_id=state['active_dialog_id'], paused=state['active_dialog_id'] is not None,
                  pause_reason='dialog' if state['active_dialog_id'] else None,
                  simulation_time=seconds(state['_sim_ms']),
                  remaining_time=max(0, config(scenario)['duration_seconds'] - seconds(state['_sim_ms'])),
                  carriages=deepcopy(config(scenario)['carriages']))
    result['incidents'] = []
    for item in state['incidents']:
        entry = {k: deepcopy(v) for k, v in item.items() if not k.startswith('_') and k not in ('success', 'timeout', 'reaction_seconds', 'service_seconds')}
        entry.update(appeared_at=seconds(item['_appeared_ms']), reaction_deadline=seconds(item['_reaction_due_ms']),
                     arrived_at=seconds(item['_arrived_ms']),
                     reaction_time=seconds(max(0, item['_reaction_due_ms'] - state['_sim_ms'])) if item['state'] in ('waiting', 'en_route') else None,
                     service_remaining=seconds(max(0, item['_service_due_ms'] - state['_sim_ms'])) if item['_service_due_ms'] is not None else None)
        result['incidents'].append(entry)
    result['staff'] = []
    for staff in state['staff']:
        entry = deepcopy(staff)
        entry.update(arrival_remaining=None, position={'from': staff['route_point_id'], 'to': staff['route_point_id'], 'progress': 1})
        if staff['route']:
            r = staff['route']
            entry['route'] = {'point_ids': r['point_ids'], 'started_at': seconds(r['_started_ms']),
                              'arrives_at': seconds(r['_arrives_ms']),
                              'segments': [{'from': s['from'], 'to': s['to'], 'starts_at': seconds(s['_starts_ms']), 'ends_at': seconds(s['_ends_ms'])} for s in r['segments']]}
            entry['arrival_remaining'] = seconds(max(0, r['_arrives_ms'] - state['_sim_ms']))
            for seg in r['segments']:
                if seg['_starts_ms'] <= state['_sim_ms'] < seg['_ends_ms']:
                    entry['position'] = {'from': seg['from'], 'to': seg['to'], 'progress': (state['_sim_ms'] - seg['_starts_ms']) / (seg['_ends_ms'] - seg['_starts_ms'])}
        result['staff'].append(entry)
    result['assignment_options'] = []
    if not state['active_dialog_id']:
        for item in state['incidents']:
            if item['state'] != 'waiting':
                continue
            for staff in state['staff']:
                if staff['state'] == 'free':
                    r = route(scenario, staff['route_point_id'], item['route_point_id'], 0)
                    result['assignment_options'].append({'incident_id': item['id'], 'staff_id': staff['id'],
                                                         'route_point_ids': r['point_ids'], 'travel_seconds': seconds(r['_arrives_ms'])})
    if main_incident(state, scenario)['state'] != 'resolving':
        result['dialog'] = None
    elif result['dialog']:
        result['dialog'].update(is_open=bool(state['active_dialog_id']), critical_decision_time=seconds(state['_decision_ms']))
    return result


def report(state, scenario):
    if state['status'] != 'completed':
        return None
    ending = scenario['nodes'][state['node_id']]
    result = {k: deepcopy(state[k]) for k in ('trip_id', 'scenario_id', 'scenario_version', 'content_status',
              'state_version', 'completed_at', 'outcome', 'facts', 'scales', 'critical_marks', 'history', 'events',
              'completed_participant_ids', 'simulation_mode', 'simulation_version')}
    result.update(summary=ending['text'], recommendation=ending['recommendation'], text_status=ending['text_status'],
                  incidents=public(state, scenario)['incidents'])
    return result
