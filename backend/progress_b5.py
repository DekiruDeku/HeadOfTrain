"""Pure, versioned history projection. No database and no client-supplied scores."""
from copy import deepcopy
import json
from pathlib import Path

try:
    from . import trip_b4
except ImportError:
    import trip_b4

DEFAULT_RULES = json.loads((Path(__file__).parent / 'data/progress-b5.json').read_text(encoding='utf-8'))


def replay(state, bundle):
    """Rebuild decisions, facts, scales and outcomes from pinned actions, not caches.

    Arrival events are evidence for dispatch timing; history holds decision order.
    Completion metadata is trusted server metadata. Reject inconsistent journals.
    """
    result = trip_b4.initial(state['trip_id'], bundle, state['conditions'], 0)
    seen = set()
    for h in state['history']:
        key = h['request_id']
        if key in seen:
            raise ValueError('Duplicate action in persisted history')
        seen.add(key)
        item = next(i for i in result['incidents'] if i['id'] == h['incident_id'])
        if item['state'] == 'completed':
            raise ValueError('Action after incident completion')
        if item['type'] == 'service':
            missed = h['source'] != 'service'
            trip_b4.service(result, bundle, item, missed)
        else:
            scenario = trip_b4.content(bundle, item)
            ctx = trip_b4.context(item)
            if h['node_before'] != ctx['node_id']:
                raise ValueError('History node does not match pinned scenario')
            if h['source'] == 'player':
                action = next(a for a in scenario['nodes'][ctx['node_id']]['actions'] if a['id'] == h['action_id'])
                if not trip_b4.available(action, ctx['conditions']):
                    raise ValueError('Unavailable persisted action')
                trip_b4.apply(result, bundle, item, action, h['request_id'])
            else:
                trip_b4.timeout(result, bundle, item, h['source'])
        generated = result['history'][-1]
        if any(generated[k] != h[k] for k in ('action_id', 'effects', 'node_after')):
            raise ValueError('History contradicts pinned content')
    if any(i['state'] != 'completed' for i in result['incidents']):
        raise ValueError('Completed trip has incomplete history')
    # end_trip derives success from reconstructed outcomes and critical marks.
    trip_b4.end_trip(result, bundle)
    for k in ('created_at', 'completed_at', 'state_version', '_last_wall_ms', '_sim_ms', 'history', 'events'):
        result[k] = deepcopy(state[k])
    for item in result['incidents']:
        arrivals = [e for e in state['events'] if e['type'] == 'arrival' and e['incident_id'] == item['id']]
        if arrivals:
            item['_arrived_ms'] = round(arrivals[0]['simulation_time'] * 1000)
            item['assigned_staff_id'] = arrivals[0]['staff_id']
    return result


def report(state, bundle):
    if state['status'] != 'completed':
        return None
    rebuilt = replay(state, bundle)
    result = trip_b4.report(rebuilt, bundle)
    rules = bundle.get('_progress_config', DEFAULT_RULES)
    points = rules['points_per_criterion']
    competencies = {k: dict(id=k, name=n, points=0, max_points=0, evidence=[]) for k,n in rules['competencies'].items()}
    scores, all_evidence = [], []
    resolved, missed, unresolved = [], [], []
    safety_ok, checks_ok = [], []
    for item in rebuilt['incidents']:
        iid = item['id']
        history = [(idx,h) for idx,h in enumerate(state['history']) if h['incident_id'] == iid]
        arrivals = [e for e in state['events'] if e['type'] == 'arrival' and e['incident_id'] == iid]
        spec = rules['scenarios'].get(item.get('scenario_id'))
        successful = item['resolution'] == 'served' if item['type'] == 'service' else trip_b4.content(bundle,item)['nodes'][trip_b4.context(item)['node_id']]['successful']
        timed_out = any(h['source'].endswith('timeout') for _,h in history)
        (resolved if successful else missed if timed_out else unresolved).append(iid)
        score = dict(incident_id=iid, scenario_id=item.get('scenario_id', 'service:'+iid),
                     scenario_version=trip_b4.content(bundle,item)['version'] if spec else bundle['version'],
                     points=0, max_points=0, competencies={}, evidence=[])

        def criterion(competency, key, met, reason, recommendation, action_indices=None, event_ids=None):
            evidence = dict(incident_id=iid, competency=competency, criterion=key, met=bool(met),
                            points=points if met else 0, max_points=points, reason=reason,
                            recommendation=recommendation, history_indices=action_indices if action_indices is not None else [idx for idx,_ in history],
                            event_ids=event_ids or [])
            score['points'] += evidence['points']
            score['max_points'] += points
            score['competencies'][competency] = score['competencies'].get(competency,0) + evidence['points']
            score['evidence'].append(evidence)
            c = competencies[competency]
            c['points'] += evidence['points']
            c['max_points'] += points
            c['evidence'].append(evidence)
            all_evidence.append(evidence)

        if spec:
            facts = trip_b4.context(item)['facts']
            checked = bool(facts.get('conditions_checked')) and not facts.get('promised_before_check', False)
            checks_ok.append(checked)
            criterion('communication', 'check_before_promise', checked,
                      'Условия проверены до обещания.' if checked else 'Условия не проверены до обещания или обращение пропущено.',
                      'Проверьте обстоятельства до обещания решения.')
            verified = bool(facts.get(spec['verification_fact']))
            if spec['safety']:
                identified = any(e['competency']=='safety' and e['criterion']=='identify_obstruction' and e['result']=='met'
                                 for _,h in history for e in h.get('competency_evidence',[]))
                criterion('safety','identify_obstruction',identified,
                          'Препятствие распознано.' if identified else 'Безопасный способ устранения препятствия не предложен.',
                          'Выясните возможность безопасного размещения багажа и предложите помощь.')
                criterion('safety','verify_result',verified and successful,
                          'Свободный проход подтверждён.' if verified and successful else 'Свободный проход не подтверждён.',
                          'После размещения багажа подтвердите, что проход свободен.')
                safety_ok.append(successful and verified)
            else:
                criterion('communication','verify_result',verified and successful,
                          'Результат договорённости проверен.' if verified and successful else 'Результат договорённости не проверен.',
                          'После решения проверьте результат у участников обращения.')
        arrived = bool(arrivals) and arrivals[0]['simulation_time'] < item['appears_at'] + item['reaction_seconds']
        criterion('prioritization','arrival_before_deadline',arrived,
                  'Сотрудник прибыл до срока реакции.' if arrived else 'Сотрудник не прибыл до срока реакции.',
                  'Назначьте свободного сотрудника с учётом времени пути до срока реакции.',
                  [], [e['id'] for e in arrivals])
        criterion('prioritization','resolved',successful,
                  'Обращение успешно завершено.' if successful else 'Обращение осталось без подтверждённого решения.',
                  'Доведите обращение до подтверждённого результата.')
        scores.append(score)
    failed = [e for e in all_evidence if not e['met']]
    # Prefer the actual safety failure, then the first concrete missed criterion.
    selected = next((e for e in failed if e['competency']=='safety'), failed[0] if failed else all_evidence[0])
    recommendation = (selected['recommendation'] if failed else
                      'Повторите «Чемодан в проходе» с другим условием размещения, сохранив проверку свободного прохода.')
    earned = ['first_trip']
    if safety_ok and all(safety_ok) and not rebuilt['critical_marks']:
        earned.append('safety_resolved')
    if checks_ok and all(checks_ok):
        earned.append('checked_before_promise')
    result.update(report_version='b5-1', scoring_version=rules['version'],
                  competencies=list(competencies.values()), scenario_scores=scores,
                  resolved_incident_ids=resolved, missed_incident_ids=missed, unresolved_incident_ids=unresolved,
                  recommendation=recommendation, recommendation_evidence=[deepcopy(selected)],
                  eligible_achievements=earned)
    return result
