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
