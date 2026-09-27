extends "res://tests/a3_scene_test.gd"

func _ready() -> void:
	await settle()
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/a5-preview.json"))
	var count: int = app.find_children("*", "", true, false).size()
	app.api.player_id = fixture.profile.player_id
	check(app.progress_api.validate("profile", fixture.profile, {}), "Accept synthetic client proposal profile")
	var invalid: Dictionary = fixture.profile.duplicate(true)
	invalid.player_id = "other-player"
	check(not app.progress_api.validate("profile", invalid, {}), "Reject another player's profile")
	invalid = fixture.profile.duplicate(true)
	invalid.competencies.safety.score = "five"
	check(not app.progress_api.validate("profile", invalid, {}), "Reject text score")
	invalid = fixture.profile.duplicate(true)
	invalid.achievements[1] = invalid.achievements[0]
	check(not app.progress_api.validate("profile", invalid, {}), "Reject duplicate achievement")
	var report: Dictionary = fixture.report
	check(app.progress_api.validate("archive", report, {"trip_id": report.trip_id}), "Accept full report proposal")
	check(not app.progress_api.validate("archive", report, {"trip_id": "wrong"}), "Reject mismatched old report")
	invalid = report.duplicate(true)
	invalid.progress.competencies[0].evidence[0].request_id = "missing"
	check(not app.progress_api.valid_report_extension(invalid), "Reject evidence missing from history")
	for route in ["correct-default", "incorrect", "missed", "critical-timeout"]:
		var real_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/api/b4/fixtures/%s/report.json" % route)).response.report
		check(app.progress_api.validate("archive", real_report, {"trip_id": real_report.trip_id}), "Accept B4 report " + route)
		app.report_screen.present(real_report)
		app.report_screen._select_section("incidents")
		check(app.report_screen.get_node("%Records").total == real_report.incidents.size(), "Every incident available")
		app.report_screen.get_node("%Records")._on_next()
		check(app.report_screen.get_node("%Records").page == 2, "Fifth incident on page two")
		app.debrief.present_report(real_report)
		for i in real_report.history.size():
			app.debrief.select_evidence(real_report.history[i].request_id)
			check(app.debrief.get_node("%Choice").text == real_report.history[i].selected_text, "Exact action from journal")
			check(app.debrief.get_node("%Evidence").text.contains(real_report.history[i].request_id), "Evidence ID preserved")
	app.report_screen.present(report)
	app.report_screen._select_section("assessment")
	var records = app.report_screen.get_node("%Records")
	var all_rows: Array = []
	while true:
		for row in records.rows:
			if row.visible:
				all_rows.append(row.get_node("%Heading").text)
		if records.get_node("%Next").disabled:
			break
		records._on_next()
	check(all_rows.size() == records.total and records.total > 15, "All assessment rows accessible beyond node pool")
	var entries: Array = fixture.leaderboard.entries
	for scope in ["crew", "depot", "company"]:
		for page in range(1, 5):
			var payload: Dictionary = fixture.leaderboard.duplicate(true)
			payload.scope = scope
			payload.page = page
			payload.entries = entries.slice((page - 1) * 3, page * 3)
			check(app.progress_api.validate("leaderboard", payload, {"scope": scope, "page": page}), "Leaderboard filter/page " + scope + str(page))
			check(not app.progress_api.validate("leaderboard", payload, {"scope": "different", "page": page}), "Reject stale filter")
			app.leaderboard_screen.scope = scope
			app.leaderboard_screen.present(payload)
			check(app.leaderboard_screen.get_node("%Records").records.size() == payload.entries.size(), "No rank row lost")
	invalid = fixture.leaderboard.duplicate(true)
	check(not app.progress_api.validate("leaderboard", invalid, {"scope": "crew", "page": 1}), "Reject oversized server page instead of truncating")
	var empty: Dictionary = fixture.leaderboard.duplicate(true)
	empty.entries = []
	empty.total = 0
	empty.own_rank = null
	check(app.progress_api.validate("leaderboard", empty, {"scope": "crew", "page": 1}), "Empty leaderboard accepted")
	app.leaderboard_screen.present(empty)
	check(app.leaderboard_screen.get_node("%Records").get_node("%Empty").visible, "Empty state visible")
	var notice: Dictionary = fixture.notifications.duplicate(true)
	notice.entries = notice.entries.slice(0, 3)
	check(app.progress_api.validate("notifications", notice, {"page": 1}), "Notification proposal accepted")
	for dimensions in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(360, 640)]:
		get_window().size = dimensions
		app.report_screen.present(report)
		app.report_screen.present_archive(fixture.profile.reports)
		app.profile_screen.present(fixture.profile)
		app.leaderboard_screen.present(empty)
		app.notifications_screen.present(notice)
		app.debrief.present_report(report)
		for index in range(3, 8):
			app.screens.current_tab = index
			await settle()
			layout(app, dimensions.x)
	check(app.profile_screen.get_node("%FutureCarriage").get_node("%Unavailable").disabled, "Third carriage always future content")
	check(app.profile_screen.get_node("%FutureCarriage").get_node("%Unlock").text == "Открыт в вашем прогрессе", "Server unlock displayed")
	app.profile_screen.loading()
	check(not app.profile_screen.get_node("%Body").visible, "Stale profile hidden during fetch")
	app.profile_screen.failed("Тест ошибки")
	check(not app.profile_screen.get_node("%Refresh").disabled, "Retry available after failure")
	app.notifications_screen.failed("Тест ошибки")
	check(app.notifications_screen.get_node("%FutureCarriage").get_node("%Unlock").text.contains("не подтверждено"), "No fake unlock on failure")
	check(count == app.find_children("*", "", true, false).size(), "Visual node count unchanged")
	print("A5_SCENE_TEST checks=%s failures=%s; B5 fixtures are synthetic CLIENT proposal" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
