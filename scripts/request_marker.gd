extends Control

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
	# Completion means a report exists, not necessarily a resolved incident.
	%Select.text = "Р" if data.state == "completed" else "!"
	%Select.tooltip_text = description
	%Select.accessibility_name = "Открыть разбор" if data.state == "completed" else "Открыть обращение: " + description
