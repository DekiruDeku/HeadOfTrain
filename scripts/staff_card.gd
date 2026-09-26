extends PanelContainer

signal staff_selected(staff_id: String)
@export var staff_id := "anna"
@export var display_name := "Анна"
@export var state_text := "Свободна · вагон 01"
@export var portrait: Texture2D

func _ready() -> void:
	%Name.text = display_name
	%State.text = state_text
	if portrait:
		%Portrait.texture = portrait

func _on_pressed() -> void:
	staff_selected.emit(staff_id)
