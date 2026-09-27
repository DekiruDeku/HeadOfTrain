"""Data-driven B1 scenario. All instructional content and scoring live in JSON."""
from copy import deepcopy
from datetime import datetime, timezone


def now():
    return datetime.now(timezone.utc).isoformat()


def available(action, state):
    return all(state['conditions'].get(key) == value for key, value in action['conditions'].items())


def enter(state, scenario, node_id):
    node = scenario['nodes'][node_id]
    for branch in node.get('branches', []):
        if all(state['conditions'].get(k) == v for k, v in branch['conditions'].items()):
            return enter(state, scenario, branch['next'])
    state['node_id'] = node_id
    state['node_entered_at'] = now()
    if 'outcome' in node:
        state['status'] = 'completed'
        state['outcome'] = node['outcome']
        state['completed_at'] = state['node_entered_at']


def initial(trip_id, condition, scenario):
    stamp = now()
    state = {
        'trip_id': trip_id, 'status': 'in_progress', 'state_version': 1,
        'scenario_id': scenario['id'], 'scenario_version': scenario['version'],
        'content_status': scenario['content_status'], 'created_at': stamp,
        'completed_at': None, 'simulation_time': 0, 'remaining_time': None,
        'clock_mode': 'untimed_b1', 'conditions': {'luggage_space': condition},
        'scales': deepcopy(scenario['initial_scales']),
        'facts': {'aisle_clear': False, 'placement': None},
        'critical_marks': [], 'history': [], 'outcome': None,
    }
    enter(state, scenario, scenario['initial_node'])
    return state


def public_state(state, scenario):
    result = deepcopy(state)
    node = scenario['nodes'][state['node_id']]
    done = state['status'] == 'completed'
    result['active_dialog_id'] = None if done else 'luggage-dialog'
    result['carriages'] = deepcopy(scenario['carriages'])
    result['staff'] = []
    result['incidents'] = [{
        **scenario['incident'], 'state': 'completed' if done else 'resolving',
        'resolution': state['outcome'], 'assigned_staff_id': None, 'reaction_time': None,
    }]
    result['dialog'] = None if done else {
        'id': 'luggage-dialog', 'scenario_id': scenario['id'], 'node_id': state['node_id'],
        'text': node['text'], 'text_status': node['text_status'],
        'critical_decision_time': None,
        'options': [{
            'id': action['id'], 'text': action['text'], 'text_status': action['text_status'],
            'available': available(action, state),
            'unavailable_reason': None if available(action, state) else action['unavailable_reason'],
        } for action in node['actions']],
    }
    return result


def apply_action(state, scenario, action, request_id):
    before = state['node_id']
    stamp = now()
    effects = action['effects']
    state['scales']['loyalty']['luggage-owner'] += effects.get('loyalty_delta', 0)
    state['scales']['safety'] += effects.get('safety_delta', 0)
    state['facts'].update(effects.get('facts', {}))
    for mark in effects.get('critical_marks', []):
        if mark not in state['critical_marks']:
            state['critical_marks'].append(mark)
    elapsed = max(0, (datetime.fromisoformat(stamp) - datetime.fromisoformat(state['node_entered_at'])).total_seconds())
    enter(state, scenario, action['next'])
    state['state_version'] += 1
    state['history'].append({
        'request_id': request_id, 'action_id': action['id'], 'incident_id': scenario['incident']['id'],
        'node_before': before, 'node_after': state['node_id'], 'selected_text': action['text'],
        'effects': deepcopy(effects), 'explanation': action['explanation'],
        'explanation_status': action['explanation_status'], 'decided_at': stamp,
        'decision_time_seconds': round(elapsed, 3),
    })
    if state['status'] == 'completed':
        state['scales']['overall_loyalty'] = state['scales']['loyalty']['luggage-owner']
        ending = scenario['nodes'][state['node_id']]
        return {
            'trip_id': state['trip_id'], 'scenario_id': scenario['id'], 'scenario_version': scenario['version'],
            'content_status': scenario['content_status'], 'state_version': state['state_version'],
            'completed_at': state['completed_at'], 'outcome': state['outcome'],
            'summary': ending['text'], 'recommendation': ending['recommendation'],
            'text_status': ending['text_status'], 'facts': deepcopy(state['facts']),
            'scales': deepcopy(state['scales']), 'critical_marks': list(state['critical_marks']),
            'history': deepcopy(state['history']),
        }
    return None
