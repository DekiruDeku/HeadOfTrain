extends Button
## One interruptible tween per control. GUI motion remains live on pause.
var motion: Tween
var reduced_motion := false

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_animate)
	mouse_exited.connect(_animate)
	focus_entered.connect(_animate)
	focus_exited.connect(_animate)
	button_down.connect(func(): _animate(true))
	button_up.connect(_animate)
	resized.connect(func(): pivot_offset = size * 0.5)
	pivot_offset = size * 0.5

func _animate(down := false) -> void:
	if motion and motion.is_valid():
		motion.kill()
	var active := not disabled and (is_hovered() or has_focus())
	var amount := 0.975 if down else (1.025 if active else 1.0)
	if reduced_motion:
		scale = Vector2.ONE
		return
	motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property(self, "scale", Vector2.ONE * amount, 0.16)
