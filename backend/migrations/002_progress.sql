CREATE TABLE profiles (
    player_id TEXT PRIMARY KEY REFERENCES players(player_id),
    display_name TEXT NOT NULL,
    is_demo INTEGER NOT NULL DEFAULT 0,
    crew_id TEXT NOT NULL,
    depot_id TEXT NOT NULL,
    company_id TEXT NOT NULL
);
CREATE TABLE best_results (
    player_id TEXT NOT NULL REFERENCES profiles(player_id),
    scenario_id TEXT NOT NULL,
    scenario_version TEXT NOT NULL,
    points INTEGER NOT NULL CHECK(points >= 0),
    competencies_json TEXT NOT NULL,
    trip_id TEXT NOT NULL REFERENCES trips(trip_id),
    PRIMARY KEY(player_id, scenario_id, scenario_version)
);
CREATE TABLE achievements (
    player_id TEXT NOT NULL REFERENCES profiles(player_id),
    achievement_id TEXT NOT NULL,
    trip_id TEXT NOT NULL REFERENCES trips(trip_id),
    earned_at TEXT NOT NULL,
    PRIMARY KEY(player_id, achievement_id)
);
CREATE TABLE content_unlocks (
    player_id TEXT NOT NULL REFERENCES profiles(player_id),
    content_id TEXT NOT NULL,
    trip_id TEXT NOT NULL REFERENCES trips(trip_id),
    PRIMARY KEY(player_id, content_id)
);
CREATE TABLE notifications (
    player_id TEXT NOT NULL REFERENCES profiles(player_id),
    notification_id TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    PRIMARY KEY(player_id, notification_id)
);
CREATE TABLE settlements (
    trip_id TEXT PRIMARY KEY REFERENCES trips(trip_id),
    player_id TEXT NOT NULL REFERENCES profiles(player_id),
    awarded INTEGER NOT NULL CHECK(awarded >= 0)
);
CREATE INDEX settlements_player ON settlements(player_id);
PRAGMA user_version = 2;
