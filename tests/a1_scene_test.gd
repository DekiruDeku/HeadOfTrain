extends Node
## Loads the saved main scene through a saved instance. No node factory in tests.

var checks := 0
var failures: Array[String] = []
@onready var app = $App

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: " + message)

func settle() -> void:
	for i in 12:
		await get_tree().process_frame

func check_horizontal(node: Node, width: float) -> void:
	if node is Control and node.is_visible_in_tree() and (node is Button or node is Label):
		var rect: Rect2 = node.get_global_rect()
		verify(rect.position.x >= -1 and rect.end.x <= width + 1, "Horizontal overflow: " + str(node.get_path()))
		verify(node.size.y + 1 >= node.get_combined_minimum_size().y, "Clipped text: " + str(node.get_path()))
	for child in node.get_children():
		check_horizontal(child, width)

func _ready() -> void:
	app.http.cancel_request()
	app.pending = ""
	await settle()
	var original_count := app.find_children("*", "", true, false).size()
	verify(app.screens.get_tab_count() == 4, "Four saved screens")
	verify(app.demo_requests.size() == 5, "Five demo records")
	var carriage: Node = app.trip.get_node("Margin/Content/MainGrid/CarriagePanel/Carriage/Map")
	verify(carriage.get_child_count() == 9, "One image, three conductors, five saved markers")
	verify(app.trip.get_node("%CrewGrid").get_child_count() == 3, "Three saved staff cards")
	app._on_demo()
	verify(app.trip.get_node("%Row1").request_id == "luggage", "First page begins with luggage")
	verify(app.trip.get_node("%Previous").disabled, "Previous disabled on first page")
	app.trip.get_node("%Next").pressed.emit()
	verify(app.trip.get_node("%Row1").request_id == "children", "Page two begins with children")
	verify(app.trip.get_node("%Row2").request_id == "seat", "Fifth record reachable")
	verify(not app.trip.get_node("%Row3").visible, "Unused third row hidden")
	verify(app.trip.get_node("%Next").disabled, "Next disabled on last page")
	for total in [0, 1, 3, 4, 7]:
		var data: Array = []
		for i in total:
			data.append(app.demo_requests[i % 5])
		app.trip.show_trip(data, "Pagination fixture")
		var pages := maxi(1, ceili(float(total) / 3))
		var visible_records := 0
		for page in pages:
			for row in app.trip.rows:
				if row.visible:
					visible_records += 1
			if page < pages - 1:
				app.trip.get_node("%Next").pressed.emit()
		verify(visible_records == total, "Pagination retains all %s records" % total)
	app._on_demo()
	carriage.get_node("Seat06/Select").pressed.emit()
	verify(app.screens.current_tab == 2, "Saved marker signal opens decision")
	verify(not app.decision.get_node("%Choice3").visible, "Two-option service hides button 3")
	app._on_back_to_trip()
	app._on_request_selected("seat")
	verify(app.decision.get_node("%Choice3").visible, "Three-option case restores button 3")
	app.decision.get_node("%Choice2").pressed.emit()
	verify(app.screens.current_tab == 3, "Choice signal opens debrief")
	verify(app.debrief.get_node("%Choice").text == app.demo_requests[4]["choices"][1], "Debrief contains chosen text")
	app.debrief.get_node("%Back").pressed.emit()
	verify(app.screens.current_tab == 1, "Debrief back signal")
	for fixture in ["{", "[]", "null", '{"ok":false}', '{"ok":true,"status":"started"}', '{"ok":true,"trip_id":"","status":"started"}', '{"ok":true,"trip_id":"X","status":"wrong"}']:
		app.screens.current_tab = 0
		app.pending = "start"
		app._on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), fixture.to_utf8_buffer())
		verify(app.screens.current_tab == 0 and not app.start.start_button.disabled, "Reject invalid response and allow retry: " + fixture)
	app.pending = "start"
	app._on_response(HTTPRequest.RESULT_SUCCESS, 500, PackedStringArray(), '{"ok":true}'.to_utf8_buffer())
	verify(app.start.get_node("%Badge").text == "НЕТ СВЯЗИ", "HTTP error shows no connection")
	app.pending = "start"
	app._on_response(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
	verify(not app.start.start_button.disabled, "Timeout permits retry")
	app.pending = "health"
	app._on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"ok":true}'.to_utf8_buffer())
	verify(app.start.get_node("%Badge").text == "СЕРВЕР НА СВЯЗИ", "Health recovery")
	app.pending = "start"
	app._on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"ok":true,"status":"started","trip_id":"TEST_ONLY"}'.to_utf8_buffer())
	verify(app.screens.current_tab == 1, "Only validated start enters trip")
	for dimensions in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(360, 640)]:
		get_window().size = dimensions
		await settle()
		for screen in 4:
			if screen == 2:
				app._on_request_selected("seat")
			app.screens.current_tab = screen
			await settle()
			check_horizontal(app.screens.get_child(screen), dimensions.x)
		print("Layout checked: %s, all four screens" % dimensions)
	verify(original_count == app.find_children("*", "", true, false).size(), "Node count unchanged after all actions")
	print("A1_SCENE_TEST checks=%s failures=%s nodes=%s" % [checks, failures.size(), original_count])
	get_tree().quit(0 if failures.is_empty() else 1)
