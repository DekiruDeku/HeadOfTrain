extends AspectRatioContainer
signal request_selected(request_id: String)
const Crew = preload("res://scripts/crew_state.gd")
var points: Dictionary = {}
var state: Dictionary = {}
var focused_carriage := ""
@onready var people: Array = [$Canvas/Anna, $Canvas/Mikhail, $Canvas/Elena]
@onready var markers: Array = [$Canvas/LuggageMarker, $Canvas/Standard/BlanketMarker, $Canvas/Standard/ChildrenMarker, $Canvas/Comfort/TableMarker, $Canvas/Comfort/SeatMarker]

func _ready() -> void:
	for point in get_tree().get_nodes_in_group("route_points"):
		if is_ancestor_of(point):
			points[point.get_meta("route_point_id")] = point
	resized.connect(_adapt)
	_adapt()

func _adapt() -> void:
	var two := state.is_empty() or Crew.enabled(state)
	var wide := size.x >= 620
	var focused := not focused_carriage.is_empty() and two
	ratio = (3.0 if wide else 0.75) if two else 1.5
	if focused:
		ratio = 1.5
	# AspectRatioContainer fits the saved Canvas into this bounded area.
	# A single carriage must not expand to a screen-tall image on desktop.
	custom_minimum_size.y = clampf(size.x / ratio, 215.0, 340.0)
	$Canvas/Standard.anchor_right = 0.49 if wide and two else 1.0
	$Canvas/Standard.anchor_bottom = 0.49 if two and not wide else 1.0
	$Canvas/Comfort.anchor_left = 0.51 if wide else 0.0
	$Canvas/Comfort.anchor_top = 0.0 if wide else 0.51
	$Canvas/Comfort.visible = two
	$Canvas/Transfer.visible = wide and two
	$Canvas/Standard.visible = true
	if focused:
		$Canvas/Standard.anchor_right = 1.0
		$Canvas/Standard.anchor_bottom = 1.0
		$Canvas/Comfort.anchor_left = 0.0
		$Canvas/Comfort.anchor_top = 0.0
		$Canvas/Standard.visible = focused_carriage == "carriage-1"
		$Canvas/Comfort.visible = focused_carriage == "carriage-2"
		$Canvas/Transfer.visible = false
	_refresh_markers()

func focus_carriage(id: String) -> void:
	focused_carriage = id
	_adapt()

func _refresh_markers() -> void:
	for marker in markers:
		marker.visible = false
		for incident in state.get("incidents", []):
			if incident.marker_id == marker.get_meta("marker_id"):
				marker.bind_incident(incident)
				marker.visible = focused_carriage.is_empty() or incident.carriage_id == focused_carriage

func bind_state(value: Dictionary) -> void:
	var was_two := state.is_empty() or Crew.enabled(state)
	state = value
	$Canvas/Standard/Title.text = state.carriages[0].name
	if state.carriages.size() > 1:
		$Canvas/Comfort/Title.text = state.carriages[1].name
	if was_two != Crew.enabled(state):
		_adapt()
	_refresh_markers()
	for person in people:
		person.visible = Crew.enabled(state)

func set_locked(value: bool) -> void:
	for marker in markers:
		marker.get_node("%Select").disabled = value

func show_time(simulation_time: float) -> void:
	if state.get("simulation_mode") in ["crew_b3", "full_b4"]:
		for incident in state.incidents:
			for marker in markers:
				if marker.get_meta("marker_id") == incident.marker_id:
					var offset := Vector2.ZERO
					# B4 services and conflicts share route points; keep both markers selectable.
					if state.get("simulation_mode") == "full_b4":
						if incident.marker_id in ["blanket-marker", "table-marker"]:
							offset.x = -marker.size.x * 0.6
						elif incident.marker_id in ["children-marker", "seat-marker"]:
							offset.x = marker.size.x * 0.6
					marker.global_position = points[incident.route_point_id].global_position - Vector2(marker.size.x / 2, marker.size.y + 12) + offset
	else:
		markers[0].global_position = points["c1-luggage"].global_position - Vector2(markers[0].size.x / 2, markers[0].size.y + 12)
	for member in state.get("staff", []):
		for person in people:
			if person.get_meta("staff_id") != Crew.visual_staff(member.id):
				continue
			person.visible = focused_carriage.is_empty() or member.carriage_id == focused_carriage
			var height := clampf($Canvas/Standard.size.y * 0.23, 32, 86)
			person.size = Vector2(height * 0.4, height)
			var feet: Vector2 = _point(member.route_point_id)
			if member.state == "moving":
				var route: Array = member.route
				feet = _point(route.back().route_point_id)
				for i in range(1, route.size()):
					if simulation_time <= float(route[i].at):
						var progress := clampf((simulation_time - float(route[i - 1].at)) / (float(route[i].at) - float(route[i - 1].at)), 0, 1)
						feet = _point(route[i - 1].route_point_id).lerp(_point(route[i].route_point_id), progress)
						break
			person.position = feet - Vector2(person.size.x / 2, person.size.y)
			person.tooltip_text = member.name + " · " + Crew.STATES[member.state]

func _point(id: String) -> Vector2:
	return points[id].global_position - $Canvas.global_position

func _on_request_selected(id: String) -> void:
	request_selected.emit(id)
