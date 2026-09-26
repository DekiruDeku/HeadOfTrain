extends ScrollContainer
signal start_requested
signal health_requested
@onready var start_button: Button = %StartButton

func _ready() -> void:
	resized.connect(_adapt_layout)
	_adapt_layout()

func _adapt_layout() -> void:
	%Body.columns = 2 if size.x >= 820 else 1
	%Image.custom_minimum_size.y = 300 if size.x >= 820 else 180

func selected_condition() -> String:
	return "occupied" if %Occupied.button_pressed else "free"

func set_state(trip: Dictionary, message: String, locked: bool) -> void:
	start_button.disabled = locked
	%HealthButton.disabled = locked
	var active: bool = trip.get("status") == "in_progress"
	%Occupied.disabled = locked or active
	%Free.disabled = locked or active
	if active:
		%Occupied.button_pressed = trip.conditions.luggage_space == "occupied"
		%Free.button_pressed = not %Occupied.button_pressed
	start_button.text = "Продолжить попытку" if active else ("Новая тренировка" if not trip.is_empty() else "Начать рейс")
	%Badge.text = "ПЕРВЫЙ СЦЕНАРИЙ · ЧЕРНОВИК"
	%Status.text = message

func _on_start_pressed() -> void:
	start_requested.emit()

func _on_health_pressed() -> void:
	health_requested.emit()
