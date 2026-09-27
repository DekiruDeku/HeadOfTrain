extends Node
const Crew = preload("res://scripts/crew_state.gd")
var checks := 0
var failures: Array = []
@onready var app = $App

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL " + label)

func settle() -> void:
	for i in 10:
		await get_tree().process_frame

func layout(node: Node, width: float) -> void:
	if node is Control and node.is_visible_in_tree() and (node is Button or node is Label):
		var rect: Rect2 = node.get_global_rect()
		check(rect.position.x >= -1 and rect.end.x <= width + 1, "Horizontal fit " + str(node.get_path()))
		check(node.size.y + 1 >= node.get_combined_minimum_size().y, "Text fit " + str(node.get_path()))
	for child in node.get_children():
		layout(child, width)

func _ready() -> void:
	await settle()
	var tape: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/a3-fixtures.json"))
	var count: int = app.find_children("*", "", true, false).size()
	var fleet = app.trip.carriage
	check(fleet.people.size() == 3, "Three saved people")
	check(fleet.markers.size() == 5, "Five saved markers")
	check(fleet.points.keys().size() == 14, "Fourteen saved route points (A3 and B3)")
	for phase in tape.phases:
		for frame in phase.frames:
			check(app.api._valid_trip(frame.trip), "Accept fixture " + phase.id + ":" + str(frame.after))
	var state: Dictionary = tape.phases[3].frames[-1].trip.duplicate(true)
	app.trip.show_trip(state)
	app.screens.current_tab = 1
	await settle()
	fleet.show_time(12)
	var anna: Vector2 = fleet.people[0].position
	var mikhail: Vector2 = fleet.people[1].position
	fleet.show_time(16)
	check(anna.is_equal_approx(fleet.people[0].position), "Serving person stays at arrival point")
	check(not mikhail.is_equal_approx(fleet.people[1].position), "Moving person interpolates route")
	var paused: Dictionary = tape.phases[4].frames[3].trip
	app.trip.show_trip(paused)
	fleet.show_time(paused.simulation_time)
	var frozen: Vector2 = fleet.people[1].position
	await settle()
	check(frozen.is_equal_approx(fleet.people[1].position), "Pause freezes route display")
	check(Crew.reaction(state.incidents[2], 0) != Crew.reaction(state.incidents[2], 2), "Reaction runs en route")
	check(Crew.reaction(state.incidents[1], 0) == Crew.reaction(state.incidents[1], 2), "Reaction stops on arrival")
	app.trip._on_request_selected("table-1")
	check(app.trip.cards[1].get_node("Content/Select").disabled, "Busy staff disabled")
	var completed: Dictionary = tape.phases[-1].frames[-1].trip
	app.trip.show_trip(completed)
	check(app.trip.cards[0].member.state == "free" and app.trip.cards[1].member.state == "free", "Both service completions shown")
	check(completed.staff[0].route_point_id == "c1-blanket" and completed.staff[1].route_point_id == "c2-table", "People remain in destination carriages")
	var invalid: Dictionary = state.duplicate(true)
	invalid.staff[1].route[1].route_point_id = "unplaced-point"
	check(not app.api._valid_trip(invalid), "Reject unplaced route")
	invalid = state.duplicate(true)
	invalid.staff[1].route[1].at = invalid.staff[1].route[0].at
	check(not app.api._valid_trip(invalid), "Reject zero-duration segment")
	invalid = state.duplicate(true)
	invalid.staff[1].id = "anna"
	check(not app.api._valid_trip(invalid), "Reject duplicate staff")
	for dimensions in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(360, 640)]:
		get_window().size = dimensions
		app.trip.show_trip(state)
		app.screens.current_tab = 1
		await settle()
		layout(app.trip, dimensions.x)
		app.decision.present(paused, paused.incidents[0])
		app.screens.current_tab = 2
		await settle()
		layout(app.decision, dimensions.x)
		print("LAYOUT " + str(dimensions))
	check(count == app.find_children("*", "", true, false).size(), "Node count unchanged")
	print("A3_SCENE_TEST checks=%s failures=%s saved_nodes=%s" % [checks, failures.size(), count])
	get_tree().quit(0 if failures.is_empty() else 1)
