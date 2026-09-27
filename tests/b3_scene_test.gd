extends "res://tests/a3_scene_test.gd"

func _ready() -> void:
	await settle()
	var root := ProjectSettings.globalize_path("res://").path_join("../docs/api/b3/")
	var frames := 0
	for filename in DirAccess.get_files_at(root.path_join("examples")):
		if not filename.ends_with(".json"):
			continue
		var tape: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("examples").path_join(filename)))
		for exchange in tape.exchanges:
			if not exchange.response.has("trip"):
				continue
			var state: Dictionary = Crew.from_wire(exchange.response.trip)
			check(app.api._valid_trip(state), "B3 full response " + filename)
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
				check(app.api._valid_acknowledgement(response), "B3 command confirmation " + exchange.path)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("fixtures/paused.json"))).response.trip
	var paused: Dictionary = Crew.from_wire(raw)
	for dimensions in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(360, 640)]:
		get_window().size = dimensions
		app.trip.show_trip(paused)
		app.screens.current_tab = 1
		await settle()
		layout(app.trip, dimensions.x)
		app.trip.carriage.show_time(paused.simulation_time)
		var marker = app.trip.carriage.markers[0]
		var comfort: Rect2 = app.trip.carriage.get_node("Canvas/Comfort").get_global_rect()
		check(comfort.has_point(marker.global_position + marker.size / 2), "B3 luggage marker in carriage 2")
		app.decision.present(paused, paused.incidents[0])
		app.screens.current_tab = 2
		await settle()
		layout(app.decision, dimensions.x)
		check(app.decision.get_node("%Place").text.begins_with("Вагон № 2"), "Dialog uses incident carriage")
	print("B3_SCENE_TEST frames=%s checks=%s failures=%s" % [frames, checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
