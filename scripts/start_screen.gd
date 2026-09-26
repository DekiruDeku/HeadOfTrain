extends ScrollContainer

signal start_requested
signal health_requested
signal demo_requested

@onready var start_button: Button = %StartButton

func _ready() -> void:
	resized.connect(_adapt_layout)
	_adapt_layout()

func _adapt_layout() -> void:
	%Body.columns = 2 if size.x >= 820 else 1
	%Image.custom_minimum_size.y = 360 if size.x >= 820 else 180

func set_pending(action: String) -> void:
	start_button.disabled = true
	%HealthButton.disabled = true
	%Status.theme_type_variation = &"Muted"
	%Status.text = "Проверяем связь с сервером…" if action == "health" else "Ждём подтверждение сервера…"

func show_success(message: String) -> void:
	start_button.disabled = false
	%HealthButton.disabled = false
	%Badge.text = "СЕРВЕР НА СВЯЗИ"
	%Badge.theme_type_variation = &"Success"
	%Status.theme_type_variation = &"Success"
	%Status.text = message

func show_error(message: String) -> void:
	start_button.disabled = false
	%HealthButton.disabled = false
	%Badge.text = "НЕТ СВЯЗИ"
	%Badge.theme_type_variation = &"Error"
	%Status.theme_type_variation = &"Error"
	%Status.text = message

func _on_start_pressed() -> void:
	start_requested.emit()

func _on_health_pressed() -> void:
	health_requested.emit()

func _on_demo_pressed() -> void:
	demo_requested.emit()
