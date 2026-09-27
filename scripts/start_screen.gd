extends Control
signal start_requested
signal health_requested
signal profile_requested
signal leaderboard_requested
signal notifications_requested

const DESIGN_SIZE := Vector2(1672, 941)
@onready var start_button: Button = %StartButton
var reduced_motion := false
var _card_tween: Tween
var _modal_tween: Tween
var _entrance: Tween
var _progress_tween: Tween
var _modal_open := false
var _previous_focus: Control
var _active_trip := false

func _ready() -> void:
	resized.connect(_adapt_layout)
	visibility_changed.connect(_on_visibility_changed)
	%StartButton.pressed.connect(func(): start_requested.emit())
	%HealthButton.pressed.connect(func(): health_requested.emit())
	%ProfileButton.pressed.connect(func(): profile_requested.emit())
	%ProfileBadge.pressed.connect(func(): profile_requested.emit())
	%LeaderboardButton.pressed.connect(func(): leaderboard_requested.emit())
	%NotificationsButton.pressed.connect(func(): notifications_requested.emit())
	%SettingsButton.pressed.connect(func(): show_settings(true))
	%CloseSettings.pressed.connect(func(): show_settings(false))
	%ModalScrim.pressed.connect(func(): show_settings(false))
	%ReduceMotion.toggled.connect(_set_reduced_motion)
	%Fullscreen.toggled.connect(_set_fullscreen)
	%FirstCard.mouse_entered.connect(func(): _lift_card(true))
	%FirstCard.mouse_exited.connect(func(): _lift_card(false))
	%StartButton.mouse_entered.connect(func(): _lift_card(true))
	%StartButton.mouse_exited.connect(func(): _lift_card(false))
	%StartButton.focus_entered.connect(func(): _lift_card(true))
	%StartButton.focus_exited.connect(func(): _lift_card(false))
	var config := ConfigFile.new()
	if config.load("user://menu-settings.cfg") == OK:
		%ReduceMotion.button_pressed = config.get_value("accessibility", "reduced_motion", false)
	%Fullscreen.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	_adapt_layout()
	play_entrance()

func _adapt_layout() -> void:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	%Design.scale = Vector2.ONE * factor
	%Design.position = (size - DESIGN_SIZE * factor) * 0.5

func _on_visibility_changed() -> void:
	if is_visible_in_tree() and is_node_ready():
		play_entrance()
	elif is_node_ready():
		if _modal_tween and _modal_tween.is_valid():
			_modal_tween.kill()
		%Modal.visible = false
		_modal_open = false
		_lift_card(false)

func play_entrance() -> void:
	if _entrance and _entrance.is_valid():
		_entrance.kill()
	%Design.modulate.a = 0.0 if not reduced_motion else 1.0
	_entrance = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_entrance.tween_property(%Design, "modulate:a", 1.0, 0.01 if reduced_motion else 0.48)

func _lift_card(hovered: bool) -> void:
	if _card_tween and _card_tween.is_valid():
		_card_tween.kill()
	var lift := hovered and not start_button.disabled and not _modal_open and not reduced_motion
	_card_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_card_tween.tween_property(%FirstCard, "position:y", 512.0 if lift else 520.0, 0.22)

func selected_condition() -> String:
	return "occupied" if %Occupied.button_pressed else "free"

func set_state(trip: Dictionary, message: String, locked: bool) -> void:
	start_button.disabled = locked
	%HealthButton.disabled = locked and not trip.is_empty()
	_active_trip = trip.get("status") == "in_progress"
	%Occupied.disabled = locked or _active_trip
	%Free.disabled = locked or _active_trip
	if _active_trip:
		%Occupied.button_pressed = trip.conditions.luggage_space == "occupied"
		%Free.button_pressed = not %Occupied.button_pressed
	start_button.set_caption("ПРОДОЛЖИТЬ" if _active_trip else "НАЧАТЬ")
	start_button.refresh_state()
	%Status.text = message
	%ConnectionHint.visible = locked
	%ConnectionHint.text = "Подключаемся к рейсу…" if locked else ""
	%ConditionNote.text = "Условия текущего рейса уже сохранены" if _active_trip else "Условия следующей тренировки"

func set_connection_error(failed: bool) -> void:
	if failed:
		%ConnectionHint.visible = true
		%ConnectionHint.text = "Нет связи · открыть настройки"
		%HealthButton.disabled = false

func present_profile(value: Dictionary) -> void:
	var display_name := str(value.get("display_name", "Ваш профиль"))
	%PlayerName.clip_text = true
	%PlayerName.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	%PlayerName.text = display_name.to_upper()
	%PlayerName.add_theme_font_size_override("font_size", 29 if display_name.length() < 17 else 22)
	var points := int(value.get("total_points", 0))
	%PlayerLevel.text = "%s очков · %s рейсов" % [points, int(value.get("completed_trips", 0))]
	if _progress_tween and _progress_tween.is_valid():
		_progress_tween.kill()
	_progress_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_progress_tween.tween_property(%PlayerProgress, "value", clampf(points / 170.0 * 100.0, 0, 100), 0.01 if reduced_motion else 0.5)
	%ProfileBadge.tooltip_text = "%s\nОткрыть профиль · %s из 170 очков" % [display_name, points]

func show_settings(open: bool) -> void:
	if _modal_tween and _modal_tween.is_valid():
		_modal_tween.kill()
	_modal_open = open
	_modal_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var duration := 0.01 if reduced_motion else 0.22
	if open:
		_previous_focus = get_viewport().gui_get_focus_owner()
		%Modal.visible = true
		%Modal.modulate.a = 0.0
		%SettingsPanel.position.y = 238
		%CloseSettings.grab_focus()
		_modal_tween.tween_property(%Modal, "modulate:a", 1.0, duration)
		_modal_tween.tween_property(%SettingsPanel, "position:y", 220.0, duration)
	else:
		_modal_tween.tween_property(%Modal, "modulate:a", 0.0, duration)
		_modal_tween.chain().tween_callback(func():
			%Modal.visible = false
			if is_instance_valid(_previous_focus):
				_previous_focus.grab_focus()
			else:
				%SettingsButton.grab_focus())

func _set_reduced_motion(value: bool) -> void:
	reduced_motion = value
	for button in %Design.find_children("*", "Button", true, false):
		if button.has_method("refresh_state"):
			button.reduced_motion = value
	var config := ConfigFile.new()
	config.set_value("accessibility", "reduced_motion", value)
	config.save("user://menu-settings.cfg")
	if value:
		_lift_card(false)

func _set_fullscreen(value: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel") and _modal_open:
		show_settings(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_down"):
		if get_viewport().gui_get_focus_owner() == null:
			(%CloseSettings if _modal_open else %TripsButton).grab_focus()
			get_viewport().set_input_as_handled()
