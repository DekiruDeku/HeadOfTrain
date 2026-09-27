"""Run all six B1 fixtures over real HTTP; optionally record exact JSON exchanges."""
import argparse
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]


def request(base_url, method, path, player_id, body=None):
    headers = {'X-Demo-Player': player_id}
    if body is not None:
        headers['Content-Type'] = 'application/json'
    req = Request(base_url + path, data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
    try:
        response = urlopen(req, timeout=10)
    except HTTPError as exc:
        response = exc
    with response:
        return response.status, json.loads(response.read())


def run_fixture(base_url, fixture):
    player_id = uuid4().hex
    exchanges = []
    def call(method, path, body=None):
        status, result = request(base_url, method, path, player_id, body)
        exchanges.append({'request': {'method': method, 'path': path, 'headers': {'X-Demo-Player': player_id, **({'Content-Type': 'application/json'} if body is not None else {})}, 'body': body}, 'response': {'status': status, 'body': result}})
        assert status == 200, result
        return result
    start_body = {'request_id': 'start-' + uuid4().hex, 'luggage_space': fixture['luggage_space']}
    started = call('POST', '/api/trips/start', start_body)
    trip = started['trip']
    path = '/api/trips/' + trip['trip_id']
    for action_id in fixture['actions']:
        body = {'request_id': uuid4().hex, 'expected_state_version': trip['state_version'], 'incident_id': 'luggage-1', 'node_id': trip['node_id'], 'action_id': action_id}
        result = call('POST', path + '/actions', body)
        assert call('POST', path + '/actions', body) == result, 'Replay changed result'
        trip = result['trip']
    report = call('GET', path + '/report')['report']
    expected = fixture['expected']
    assert trip['status'] == 'completed'
    assert report['outcome'] == expected['outcome']
    assert report['scales']['loyalty']['luggage-owner'] == expected['loyalty']
    assert report['scales']['safety'] == expected['safety']
    assert report['facts']['aisle_clear'] == expected['aisle_clear']
    assert trip['state_version'] == expected['state_version']
    assert len(report['history']) == len(fixture['actions'])
    assert call('GET', '/api/trips/current')['trip'] == trip
    assert call('GET', path)['trip'] == trip
    assert call('POST', '/api/trips/start', start_body) == started
    assert call('GET', '/api/trips/current')['trip'] == trip
    return {'fixture_id': fixture['id'], 'content_status': 'draft', 'exchanges': exchanges}


def run_errors(base_url):
    player_id = uuid4().hex
    exchanges = []
    def call(method, path, body=None, expected=200):
        status, result = request(base_url, method, path, player_id, body)
        exchanges.append({'request': {'method': method, 'path': path, 'headers': {'X-Demo-Player': player_id, **({'Content-Type': 'application/json'} if body is not None else {})}, 'body': body}, 'response': {'status': status, 'body': result}})
        assert status == expected, result
        return result
    call('GET', '/api/trips/current', expected=404)
    trip = call('POST', '/api/trips/start', {'request_id': 'start', 'luggage_space': 'occupied'})['trip']
    path = '/api/trips/' + trip['trip_id']
    call('GET', path + '/report', expected=409)
    body = {'request_id': 'choice', 'expected_state_version': 1, 'incident_id': 'luggage-1', 'node_id': 'opening', 'action_id': 'offer_help'}
    call('POST', path + '/actions', {**body, 'action_id': 'unknown'}, expected=422)
    call('POST', path + '/actions', {**body, 'node_id': 'conflict'}, expected=422)
    applied = call('POST', path + '/actions', body)
    call('POST', path + '/actions', {**body, 'action_id': 'allow_luggage'}, expected=409)
    call('POST', path + '/actions', {**body, 'request_id': 'stale'}, expected=409)
    call('POST', path + '/actions', {**body, 'request_id': 'unavailable', 'expected_state_version': 2, 'node_id': 'space_occupied', 'action_id': 'place_free'}, expected=422)
    assert call('GET', path)['trip'] == applied['trip']
    call('POST', '/api/trips/start', {'request_id': 'active', 'new_attempt': True}, expected=409)
    call('POST', '/api/trips/start', {'request_id': 'condition', 'luggage_space': 'free'}, expected=409)
    call('POST', path + '/actions', {**body, 'request_id': 'version-type', 'expected_state_version': True}, expected=400)
    call('POST', path + '/actions', {**body, 'request_id': 'client-score', 'scales': {'safety': 100}}, expected=400)
    final_body = {**body, 'request_id': 'finish', 'expected_state_version': 2, 'node_id': 'space_occupied', 'action_id': 'repeat_request'}
    completed = call('POST', path + '/actions', final_body)
    call('POST', path + '/actions', {**final_body, 'request_id': 'after-completion', 'expected_state_version': 3, 'node_id': 'unresolved'}, expected=409)
    call('GET', path + '/report')
    # Old successful response may be stale, but must not rewind saved state.
    assert call('POST', path + '/actions', body) == applied
    assert call('GET', path)['trip'] == completed['trip']
    return {'fixture_id': 'errors', 'exchanges': exchanges}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url', default='http://127.0.0.1:8765')
    parser.add_argument('--record', type=Path, help='Write actual HTTP exchanges to this directory')
    args = parser.parse_args()
    for path in sorted((ROOT / 'docs/api/fixtures').glob('*.json')):
        result = run_fixture(args.base_url.rstrip('/'), json.loads(path.read_text(encoding='utf-8')))
        if args.record:
            args.record.mkdir(parents=True, exist_ok=True)
            (args.record / path.name).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f"PASS {result['fixture_id']}: HTTP scenario, replay, report, recovery")
    result = run_errors(args.base_url.rstrip('/'))
    if args.record:
        (args.record / 'errors.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('PASS errors: 400 / 404 / 409 / 422, rejected requests and stale replay preserve state')


if __name__ == '__main__':
    main()
