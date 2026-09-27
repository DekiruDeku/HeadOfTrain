extends "res://tests/a3_scene_test.gd"

func _ready() -> void:
	await settle()
	var root := ProjectSettings.globalize_path("res://../docs/api/b4/")
	var frames := 0
	for filename in DirAccess.get_files_at(root.path_join("http-exchanges")):
		var tape: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("http-exchanges").path_join(filename)))
		for exchange in tape.exchanges:
			if not exchange.response.has("trip"):
				continue
			var state: Dictionary = Crew.from_wire(exchange.response.trip)
			check(app.api._valid_trip(state), "B4 response " + filename)
			if not app.api._valid_trip(state):
				continue
			frames += 1
			app.trip.show_trip(state)
			app.trip.carriage.show_time(state.simulation_time)
			if exchange.method == "POST":
				app.api.player_id = tape.player_id
				app.api.pending_post = {"path": exchange.path, "body": JSON.stringify(exchange.body)}
				var response: Dictionary = exchange.response.duplicate(true)
				response.trip = state
				check(app.api._valid_acknowledgement(response), "B4 acknowledgement " + exchange.path)
	for path in ["correct-default", "correct-alternative", "incorrect", "missed", "critical-timeout"]:
		var completed: Dictionary = Crew.from_wire(JSON.parse_string(FileAccess.get_file_as_string(root.path_join("fixtures/" + path + "/completed.json"))).response.trip)
		var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("fixtures/" + path + "/report.json"))).response.report
		app.api.trip_id = completed.trip_id
		app.api.trip = completed
		check(app.api._valid_report(report), "B4 report " + path)
		app.debrief.present_report(report, completed)
	var paused: Dictionary = Crew.from_wire(JSON.parse_string(FileAccess.get_file_as_string(root.path_join("fixtures/correct-default/children-1-verify.json"))).response.trip)
	check(paused.dialog.incident_id == "children-1", "Explicit B4 dialog binding")
	for dimensions in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(360, 640)]:
		get_window().size = dimensions
		app.trip.show_trip(paused)
		app.screens.current_tab = 1
		await settle()
		app.trip.carriage.show_time(paused.simulation_time)
		layout(app.trip, dimensions.x)
		var fleet = app.trip.carriage
		check(not fleet.markers[1].get_global_rect().intersects(fleet.markers[2].get_global_rect()), "B4 markers do not overlap")
		for incident in paused.incidents:
			if incident.id == paused.dialog.incident_id:
				app.decision.present(paused, incident)
		app.screens.current_tab = 2
		await settle()
		layout(app.decision, dimensions.x)
		check(app.decision.get_node("%LastEffect").text.contains("семья"), "Both sides of conflict displayed")
	var boundary: Dictionary = paused.duplicate(true)
	boundary.next_incident_time = boundary.simulation_time + 0.25
	# from_wire takes wire routes, so use a fresh unadapted fixture.
	boundary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("fixtures/correct-default/initial.json"))).response.trip
	boundary.next_incident_time = boundary.simulation_time + 0.25
	check(Crew.from_wire(boundary).display_horizon == 0.25, "Interpolation stops at next arrival")
	check(Crew.status_key({"state": "completed", "resolution": "conflict"}) == "issue", "Escalated conflict is an issue")
	print("B4_SCENE_TEST frames=%s checks=%s failures=%s" % [frames, checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
