extends "res://tests/a3_scene_test.gd"

func fixture(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://../docs/api/b5/recorded/fixtures/" + path + ".json")).response

func _ready() -> void:
	await settle()
	app.api.player_id = "b5000000000000000000000000000001"
	for state in ["empty", "incorrect", "improved", "repeat-best", "repeat-equal", "repeat-worse"]:
		var profile: Dictionary = fixture(state + "/profile").profile
		check(app.progress_api.validate("profile", profile, {}), "B5 profile " + state)
		app.profile_screen.present(profile)
		app.profile_screen._show_archive()
		check(app.profile_screen.records.filter(func(r): return r.has("target")).size() == profile.report_ids.size(), "Complete profile archive")
		app.profile_screen._show_best()
		check(app.profile_screen.records.filter(func(r): return r.has("target")).size() == profile.best_results.size(), "Complete personal records")
		app.profile_screen._close_modal(true)
		var invalid: Dictionary = profile.duplicate(true)
		invalid.player_id = "other"
		check(not app.progress_api.validate("profile", invalid, {}), "Reject foreign profile")
		invalid = profile.duplicate(true)
		invalid.achievements[1] = invalid.achievements[0]
		check(not app.progress_api.validate("profile", invalid, {}), "Reject duplicate achievement")
		for kind in ["leaderboard", "notifications"]:
			var data: Dictionary = fixture(state + "/" + kind)
			data.page_size = 3
			if kind == "leaderboard":
				data.entries = data.entries.slice(0, 3)
			check(app.progress_api.validate(kind, data, {"page": 1, "scope": "crew"}), "B5 " + kind + " " + state)
			app._progress_screen(kind).present(data)
		if state == "empty":
			continue
		var report: Dictionary = fixture(state + "/report").report
		check(app.progress_api.validate("archive", report, {"trip_id": report.trip_id}), "B5 report " + state)
		app.report_screen.present(report)
		app.report_screen._select_section("assessment")
		check(app.report_screen.get_node("%Points").text.contains("+%s" % int(report.points.awarded)), "Actual awarded points")
		invalid = report.duplicate(true)
		invalid.competencies[0].evidence[0].history_indices = [99999]
		check(not app.progress_api.valid_report_extension(invalid), "Reject invalid evidence index")
		var visible_rows := 0
		while true:
			var shown: String = app.report_screen.get_node("%RecordTitle").text
			check(shown == app.report_screen.records[visible_rows].title, "Exact assessment record is rendered")
			visible_rows += 1
			if app.report_screen.get_node("%Next").disabled: break
			app.report_screen._move_record(1)
		check(visible_rows == app.report_screen.records.size(), "Every evidence and scenario score accessible")
	for scope in ["crew", "depot", "company"]:
		var data: Dictionary = fixture("leaderboards/" + scope + "-1")
		data.page_size = 3
		data.entries = data.entries.slice(0, 3)
		# These recorded pages use size 2; validation below checks stale selection.
		check(not app.progress_api.validate("leaderboard", data, {"page": 1, "scope": "wrong"}), "Reject stale scope")
	for route in ["correct-default", "incorrect", "missed", "critical-timeout"]:
		var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/api/b4/fixtures/%s/report.json" % route)).response.report
		check(app.progress_api.validate("archive", report, {"trip_id": report.trip_id}), "Legacy B4 " + route)
	print("B5_SCENES checks=%s failures=%s" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
