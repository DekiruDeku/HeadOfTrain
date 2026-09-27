extends Button
## Stable hit rect: only artwork moves, so hovering an edge cannot flicker.
@export var selected := false
@export var primary := false
@export var quiet := false
var reduced_motion := false
var _hovered := false
var _tween: Tween

func _ready() -> void:
	mouse_entered.connect(func(): _hovered = true; _refresh())
	mouse_exited.connect(func(): _hovered = false; _refresh())
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	button_down.connect(func(): _refresh(true))
	button_up.connect(func(): _refresh())
	toggled.connect(func(_value: bool): _refresh())
	_refresh()

func _refresh(pressed_down := false) -> void:
	if not is_node_ready():
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	var lit := (_hovered or has_focus()) and not disabled
	var active := selected or primary or button_pressed
	var ink := get_theme_color("ink" if active else "muted", "Palette")
	if lit and not active:
		ink = get_theme_color("paper", "Palette")
	if disabled:
		ink.a = 0.5
	$Visual/Focus.visible = has_focus() and not disabled
	var fill_alpha := 1.0 if active else (0.13 if lit else 0.0)
	if quiet:
		fill_alpha = 0.08 if lit else 0.0
	$Visual.pivot_offset = size * 0.5
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var duration := 0.01 if reduced_motion else (0.09 if pressed_down else 0.20)
	_tween.tween_property($Visual/Fill, "modulate:a", fill_alpha, duration)
	_tween.tween_property($Visual/Foreground, "modulate", ink, duration)
	_tween.tween_property($Visual/Foreground, "position:x", 5.0 if lit and not quiet else 0.0, duration)
	_tween.tween_property($Visual, "scale", Vector2(0.982, 0.982) if pressed_down else Vector2.ONE, duration)
	_tween.tween_property($Visual/Fill, "self_modulate", Color(1.12, 1.09, 1.02) if lit else Color.WHITE, duration)

func refresh_state() -> void:
	_refresh()

func set_caption(value: String) -> void:
	text = value
	$Visual/Foreground/Caption.text = value
	tooltip_text = value.capitalize()
	var arrow := $Visual/Foreground.get_node_or_null("Arrow")
	if primary and arrow:
		var caption: Label = $Visual/Foreground/Caption
		var width := caption.get_theme_font("font").get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, caption.get_theme_font_size("font_size")).x
		caption.position.x = (size.x - width - 54.0) * 0.5
		caption.size.x = width + 2.0
		arrow.position.x = caption.position.x + width + 20.0
