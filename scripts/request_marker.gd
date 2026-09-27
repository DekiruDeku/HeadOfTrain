extends Control
const Crew = preload("res://scripts/crew_state.gd")

signal request_selected(request_id: String)
@export var request_id := "luggage"
@export var number := "01"
@export var description := "Чемодан в проходе · место 18"

func _ready() -> void:
	%Select.text = number
	%Select.tooltip_text = description
	%Select.accessibility_name = description

func _on_pressed() -> void:
	request_selected.emit(request_id)

func bind_incident(data: Dictionary) -> void:
	request_id = data.id
	description = data.text
	%Select.text = Crew.symbol(data)
	var key := Crew.status_key(data)
	%Select.theme_type_variation = {"resolved": &"ResolvedMarker", "missed": &"MissedMarker", "issue": &"MissedMarker", "en_route": &"MovingMarker", "resolving": &"MovingMarker"}.get(key, &"WaitingMarker")
	%Select.tooltip_text = description + "\n" + Crew.status_text(data) + " · " + Crew.priority_text(data)
	%Select.accessibility_name = %Select.tooltip_text
