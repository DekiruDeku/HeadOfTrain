#!/usr/bin/env bash
# Complete one free-space path using actual HTTP. Python is only a JSON helper.
set -eu
base_url="${1:-http://127.0.0.1:8765}"
demo_player="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
start_request="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
response="$(curl --fail --silent --show-error -H "X-Demo-Player: $demo_player" -H 'Content-Type: application/json' --data "{\"request_id\":\"$start_request\",\"luggage_space\":\"free\"}" "$base_url/api/trips/start")"
trip_id="$(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin)["trip_id"])')"
for action_id in offer_help place_free confirm_clear; do
    action_body="$(printf '%s' "$response" | python3 -c 'import json,sys,uuid; t=json.load(sys.stdin)["trip"]; print(json.dumps({"request_id":uuid.uuid4().hex,"expected_state_version":t["state_version"],"incident_id":"luggage-1","node_id":t["node_id"],"action_id":sys.argv[1]}))' "$action_id")"
    response="$(curl --fail --silent --show-error -H "X-Demo-Player: $demo_player" -H 'Content-Type: application/json' --data "$action_body" "$base_url/api/trips/$trip_id/actions")"
done
# Restore without a locally stored trip_id, then read the saved report.
curl --fail --silent --show-error -H "X-Demo-Player: $demo_player" "$base_url/api/trips/current" | python3 -m json.tool
curl --fail --silent --show-error -H "X-Demo-Player: $demo_player" "$base_url/api/trips/$trip_id/report" | python3 -m json.tool
