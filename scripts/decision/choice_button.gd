extends Button
## The hit rectangle stays still while the printed face lifts inside it.
var number := 1
var reduced_motion := false
var active := 0.0:
	set(value):
		active = value
		queue_redraw()
var press_depth := 0.0:
	set(value):
		press_depth = value
		queue_redraw()
var selected := false
var _hover: Tween
var _press: Tween
var copy: Label
var font_size := 25

func _ready() -> void:
	clip_text = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size.y = 64
	copy = Label.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(copy)
	resized.connect(_layout)
	mouse_entered.connect(_mouse_entered)
	mouse_exited.connect(_refresh)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	button_down.connect(_push.bind(1.0))
	button_up.connect(_push.bind(0.0))
	_layout()

func configure(value: String, available: bool, reason: String, compact: bool) -> void:
	text = value # Keep accessible/diagnostic text on the native Button.
	font_size = 18 if compact else 25
	copy.text = value + ("\n" + reason if not available else "")
	copy.add_theme_font_size_override("font_size",font_size)
	copy.add_theme_color_override("font_color",get_theme_color("ink" if available else "muted","Palette"))
	tooltip_text = reason if not available else ""
	_layout()

func _layout() -> void:
	if not is_instance_valid(copy): return
	var gutter := 36.0 if font_size == 18 else 72.0
	var inset := 12.0 if font_size == 18 else 18.0
	var end := 32.0 if font_size == 18 else 39.0
	copy.position = Vector2(gutter + inset, 7)
	copy.size = Vector2(maxf(20,size.x-gutter-inset-end),size.y-14)
	var text_height := copy.get_theme_font("font").get_multiline_string_size(copy.text,HORIZONTAL_ALIGNMENT_LEFT,maxf(180,size.x-gutter-inset-end),font_size).y
	custom_minimum_size.y = maxf(58 if font_size == 18 else 64,text_height+18)
	queue_redraw()

func _mouse_entered() -> void:
	var previous := get_viewport().gui_get_focus_owner()
	if previous and previous != self and previous.get_parent() == get_parent():
		previous.release_focus()
	_refresh()

func _refresh() -> void:
	if _hover and _hover.is_valid(): _hover.kill()
	var target := 1.0 if selected or (not disabled and (is_hovered() or has_focus())) else 0.0
	if reduced_motion:
		active = target
		return
	_hover = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover.tween_property(self,"active",target,0.17)

func _push(value: float) -> void:
	if _press and _press.is_valid(): _press.kill()
	if reduced_motion:
		press_depth = value
		return
	_press = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_press.tween_property(self,"press_depth",value,0.09)

func reset_feedback() -> void:
	selected = false
	press_depth = 0.0
	_refresh()

func _shape(rect: Rect2, cut: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	return PackedVector2Array([p+Vector2(cut,0),Vector2(e.x-cut,p.y),Vector2(e.x,p.y+cut),e-Vector2(0,cut),e-Vector2(cut,0),Vector2(p.x+cut,e.y),Vector2(p.x,e.y-cut),p+Vector2(0,cut)])

func _draw() -> void:
	if size.x < 90 or size.y < 22: return
	var lift := 0.0 if reduced_motion else active*2.5-press_depth*2.0
	var rect := Rect2(Vector2(0,3-lift),size-Vector2(0,5))
	var points := _shape(rect,9)
	var shadow := _shape(Rect2(rect.position+Vector2(0,3),rect.size),9)
	draw_colored_polygon(shadow,Color(0.18,0.12,0.06,0.15))
	var fill := get_theme_color("paper","Palette").lerp(Color("fffaf0"),active*0.85)
	draw_colored_polygon(points,fill)
	var gold := get_theme_color("gold","Palette").lerp(Color("e1b870"),active)
	if disabled and not selected: gold = gold.lerp(fill,0.4)
	var gutter := 36.0 if font_size == 18 else 72.0
	var badge := PackedVector2Array([points[0],Vector2(gutter,rect.position.y),Vector2(gutter,rect.end.y),points[5],points[6],points[7]])
	draw_colored_polygon(badge,gold)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline,Color("bca98c").lerp(Color("987446"),active),1.2,true)
	var ink := get_theme_color("ink","Palette")
	var font := preload("res://assets/fonts/Oswald-Bold.ttf")
	var nsize := 29 if font_size == 18 else 38
	var digits := str(number)
	var width := font.get_string_size(digits,HORIZONTAL_ALIGNMENT_LEFT,-1,nsize).x
	draw_string(font,Vector2((gutter-width)*0.5,(size.y+font.get_ascent(nsize)-font.get_descent(nsize))*0.5-lift),digits,HORIZONTAL_ALIGNMENT_LEFT,-1,nsize,ink)
	var x: float = size.x-30+(0.0 if reduced_motion else active*4.0)
	var y := size.y*0.5-lift
	if selected:
		draw_polyline(PackedVector2Array([Vector2(x-7,y),Vector2(x-2,y+5),Vector2(x+7,y-6)]),ink,2.4,true)
	elif not disabled:
		draw_polyline(PackedVector2Array([Vector2(x-4,y-7),Vector2(x+3,y),Vector2(x-4,y+7)]),ink,2.3,true)
	if has_focus() and not disabled:
		draw_polyline(outline,ink,2.0,true)
