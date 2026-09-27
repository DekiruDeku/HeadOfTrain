extends "res://tests/a3_scene_test.gd"
## UI stress data only. Not B4 scenarios and never sent to the backend.

func _ready() -> void:
	await settle()
	var path := ProjectSettings.globalize_path("res://../docs/api/b3/fixtures/paused.json")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)).response.trip
	var state: Dictionary = Crew.from_wire(raw)
	var nodes: int = app.find_children("*", "", true, false).size()
	check(get_tree().get_nodes_in_group("passengers").size() == 6, "Six passengers saved in scene")
	for passenger in get_tree().get_nodes_in_group("passengers"):
		check(passenger.texture != null, "Saved passenger texture " + passenger.name)
	# Two extra presentation rows exercise reserved markers and pagination only.
	for spec in [["children-ui", "children-marker", "carriage-1"], ["seat-ui", "seat-marker", "carriage-2"]]:
		var item: Dictionary = state.incidents[0].duplicate(true)
		item.id = spec[0]
		item.marker_id = spec[1]
		item.carriage_id = spec[2]
		item.route_point_id = "c1-aisle" if spec[2] == "carriage-1" else "c2-exit"
		item.text = "Только проверка компоновки: длинное обращение, условия и пояснения. ".repeat(3)
		item.state = "waiting"
		state.incidents.append(item)
	state.incidents[1].state = "completed"
	state.incidents[1].resolution = "missed"
	state.incidents[2].state = "completed"
	state.incidents[2].resolution = "served"
	app.trip.show_trip(state)
	app.screens.current_tab = 1
	await settle()
	check(app.trip.carriage.markers[1].get_node("%Select").text == "×", "Missed is not success")
	check(app.trip.carriage.markers[3].get_node("%Select").text == "✓", "Served marker")
	app.trip._on_request_selected("seat-ui")
	check(app.trip.page == 1 and app.trip.rows[1].request_id == "seat-ui", "Marker selects correct list page")
	check(app.trip.get_node("%Overview").text.contains("пропущено: 1"), "Missed counted in overview")
	for dimensions in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(360, 640)]:
		get_window().size = dimensions
		app.screens.current_tab = 1
		for carriage_id in ["", "carriage-1", "carriage-2"]:
			app.trip._on_carriage_selected(carriage_id)
			await settle()
			app.trip.carriage.show_time(state.simulation_time)
			layout(app.trip, dimensions.x)
			for marker in app.trip.carriage.markers:
				if marker.is_visible_in_tree():
					check(marker.get_global_rect().size.y >= marker.get_node("%Select").get_combined_minimum_size().y, "Marker fits status")
		app.trip.set_locked(true)
		await settle()
		layout(app.trip, dimensions.x)
		app.trip.set_locked(false)
		app.decision.present(state, state.incidents[0])
		app.decision.get_node("%Description").text = "Длинная реплика для проверки чтения и прокрутки. ".repeat(50)
		app.decision.options[0].available = false
		app.decision.get_node("%Choice1").text = "Недоступно: ".repeat(30) + "условия не выполнены."
		app.decision.set_locked(false)
		app.screens.current_tab = 2
		await settle()
		layout(app.decision, dimensions.x)
		check(app.decision.get_node("%Choice1").disabled, "Unavailable option remains disabled")
		app.decision.ensure_control_visible(app.decision.get_node("%Cancel"))
		await settle()
		check(app.decision.scroll_vertical > 0, "Long dialog can scroll to last control")
		print("A4_LAYOUT " + str(dimensions))
	var ambiguous: Dictionary = raw.duplicate(true)
	var extra: Dictionary = raw.incidents[0].duplicate(true)
	extra.id = "children-ui"
	extra.marker_id = "children-marker"
	ambiguous.incidents.append(extra)
	check(Crew.from_wire(ambiguous).is_empty(), "Ambiguous dialog fails closed")
	ambiguous.dialog.incident_id = "luggage-1"
	check(Crew.from_wire(ambiguous).dialog.incident_id == "luggage-1", "Explicit incident_id preserved with two resolving requests")
	var completed_path := ProjectSettings.globalize_path("res://../docs/api/b3/fixtures/completed-with-mark.json")
	var completed: Dictionary = Crew.from_wire(JSON.parse_string(FileAccess.get_file_as_string(completed_path)).response.trip)
	var completions: Array = []
	app.trip_completed.connect(func(id: String): completions.append(id))
	app.api.trip = completed
	app._on_state_received("poll")
	app._on_state_received("restore")
	check(completions == [completed.trip_id], "One completion signal per trip per mounted client")
	check(nodes == app.find_children("*", "", true, false).size(), "No runtime nodes added")
	print("A4_SCENE_TEST checks=%s failures=%s saved_nodes=%s" % [checks, failures.size(), nodes])
	get_tree().quit(0 if failures.is_empty() else 1)
