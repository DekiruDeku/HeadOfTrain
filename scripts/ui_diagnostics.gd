extends Node
## Opt-in read-only browser QA: ?qa=1. No actions, credentials or node factories.
var elapsed := 0.0

func _ready() -> void:
	set_process(OS.has_feature("web") and str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('qa')")) == "1")

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.15:
		return
	elapsed = 0.0
	var controls: Array = []
	_collect(get_parent(), controls)
	var api = get_parent().api
	var snapshot := {"controls": controls, "screen": get_parent().screens.current_tab, "busy": api.busy, "ready": api.ready_for_input, "error": api.error_code, "version": api.trip.get("state_version"), "node": api.trip.get("node_id"), "node_count": get_parent().find_children("*", "", true, false).size()}
	snapshot.paused = api.trip.get("paused", false)
	snapshot.simulation_time = api.trip.get("simulation_time")
	snapshot.staff = api.trip.get("staff", [])
	snapshot.incidents = api.trip.get("incidents", [])
	snapshot.trip_id = api.trip.get("trip_id")
	snapshot.status = api.trip.get("status")
	snapshot.history = api.trip.get("history", [])
	snapshot.dialog = api.trip.get("dialog")
	snapshot.focused_carriage = get_parent().trip.focused_carriage
	snapshot.completion_trip_id = get_parent().announced_completion
	snapshot.people = []
	for person in get_parent().trip.carriage.people:
		snapshot.people.append({"id": person.get_meta("staff_id"), "x": person.position.x, "y": person.position.y})
	JavaScriptBridge.eval("window.__hotQA=" + JSON.stringify(snapshot))

func _collect(node: Node, controls: Array) -> void:
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button):
		var rect: Rect2 = node.get_global_rect()
		controls.append({"path": str(get_parent().get_path_to(node)), "text": node.text, "button": node is Button, "disabled": node.disabled if node is Button else false, "x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y, "min_h": node.get_combined_minimum_size().y})
	for child in node.get_children():
		_collect(child, controls)
