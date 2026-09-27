extends PanelContainer

signal staff_selected(staff_id: String)
@export var staff_id := "anna"
@export var display_name := "Анна"
@export var state_text := "Свободна · вагон 01"
@export var portrait: Texture2D
const Crew = preload("res://scripts/crew_state.gd")
var member: Dictionary = {}
var can_assign := false
var locked := false

func _ready() -> void:
	%Name.text = display_name
	%State.text = state_text
	if portrait:
		%Portrait.texture = portrait

func _on_pressed() -> void:
	if can_assign and not locked:
		staff_selected.emit(staff_id)

func bind_member(data: Dictionary, eta: Variant, selectable: bool, simulation_time: float) -> void:
	member = data
	staff_id = data.id
	%Name.text = data.name
	var carriage := "01" if data.carriage_id == "carriage-1" else "02"
	%State.text = Crew.STATES[data.state] + " · вагон " + carriage
	if data.state == "moving":
		%State.text += "\nПрибудет через " + Crew.seconds(float(data.arrival_time) - simulation_time)
	elif data.state == "serving" and data.get("service_end_time") != null:
		%State.text += "\nОсвободится через " + Crew.seconds(float(data.service_end_time) - simulation_time)
	can_assign = selectable and data.state == "free" and eta != null
	$Content/Select.text = "Назначить · ≈ " + Crew.seconds(eta) if can_assign else ("Занят" if data.state != "free" else "Выберите обращение")
	$Content/Select.disabled = locked or not can_assign

func set_locked(value: bool) -> void:
	locked = value
	$Content/Select.disabled = locked or not can_assign
