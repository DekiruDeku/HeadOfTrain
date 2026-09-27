"""Enumerate data paths independently of the runtime; expected scale deltas for QA."""
from itertools import product


def paths(scenario, conditions):
    def visit(node_id, actions, effects):
        node = scenario['nodes'][node_id]
        if 'outcome' in node:
            yield dict(conditions=conditions, actions=actions, node_id=node_id,
                       outcome=node['outcome'], successful=node['successful'], effects=effects,
                       explanation=node['text'])
        elif 'branches' in node:
            for b in node['branches']:
                if all(conditions.get(k) == v for k,v in b['conditions'].items()):
                    yield from visit(b['next'], actions, effects)
        else:
            for a in node['actions']:
                if all(conditions.get(k) == v for k,v in a['conditions'].items()):
                    e = {'loyalty_deltas':dict(effects['loyalty_deltas']),
                         'safety_delta':effects['safety_delta'] + a['effects'].get('safety_delta',0)}
                    for p,d in a['effects'].get('loyalty_deltas',{}).items():
                        e['loyalty_deltas'][p] = e['loyalty_deltas'].get(p,0)+d
                    yield from visit(a['next'],actions+[a['id']],e)
    yield from visit(scenario['initial_node'],[],{'loyalty_deltas':{},'safety_delta':0})


def all_paths(bundle):
    result=[]
    for s in bundle['scenarios'].values():
        for values in product(*s['condition_schema'].values()):
            conditions=dict(zip(s['condition_schema'],values))
            result.extend({'scenario_id':s['id'],**p} for p in paths(s,conditions))
    return result


def correct_actions(conditions):
    return {
        'luggage-1':['offer_help','place_free' if conditions['luggage_space']=='free' else 'place_alternative','confirm_clear'],
        'children-1':['clarify','offer_move' if conditions['relocation']=='available' else 'agree_quiet','verify_agreement'],
        'seat-1':['check_ticket','guide' if conditions['seat_reason']=='mistake' else 'explain_return','verify_seats'],
    }
