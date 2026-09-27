CREATE TABLE players (
    player_id TEXT PRIMARY KEY,
    current_trip_id TEXT
);
CREATE TABLE trips (
    trip_id TEXT PRIMARY KEY,
    player_id TEXT NOT NULL REFERENCES players(player_id),
    state_json TEXT NOT NULL,
    scenario_json TEXT NOT NULL,
    report_json TEXT
);
CREATE INDEX trips_player ON trips(player_id);
CREATE TABLE requests (
    player_id TEXT NOT NULL REFERENCES players(player_id),
    request_id TEXT NOT NULL,
    fingerprint TEXT NOT NULL,
    response_json TEXT NOT NULL,
    PRIMARY KEY (player_id, request_id)
);
PRAGMA user_version = 1;
