extends AspectRatioContainer
signal request_selected(request_id: String)
@onready var markers: Array = [$Map/Seat18, $Map/Seat06, $Map/Seat24, $Map/Seat12, $Map/Seat28]

func bind_incidents(incidents: Array) -> void:
	$Map/Anna.visible = false
	$Map/Mikhail.visible = false
	$Map/Elena.visible = false
	for marker in markers:
		marker.visible = false
	for incident in incidents:
		if incident.marker_id == "luggage-marker":
			$Map/Seat18.bind_incident(incident)
			$Map/Seat18.visible = true

func set_locked(value: bool) -> void:
	for marker in markers:
		marker.get_node("%Select").disabled = value

func _on_request_selected(request_id: String) -> void:
	request_selected.emit(request_id)
