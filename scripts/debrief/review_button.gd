extends Button
## Animate the printed face, leaving the hit rectangle and focus layout stable.
var kind := "secondary"
var step_index := -1
var selected := false
var compact := false
var portrait: Texture2D
var reduced_motion := false
var active := 0.0:
	set(value):
		active = value
		queue_redraw()
var depth := 0.0:
	set(value):
		depth = value
		queue_redraw()
var portrait_view: TextureRect
var portrait_mask: Control
var _motion: Tween
var _press: Tween
func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	portrait_view = TextureRect.new()
	portrait_view.texture = portrait
	portrait_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_mask = preload("res://scripts/debrief/portrait_mask.gd").new()
	add_child(portrait_mask)
	portrait_mask.add_child(portrait_view)
	portrait_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_entered.connect(refresh)
	mouse_exited.connect(refresh)
	focus_entered.connect(refresh)
	focus_exited.connect(refresh)
	button_down.connect(_push.bind(1.0))
	button_up.connect(_push.bind(0.0))
	resized.connect(queue_redraw)
func refresh() -> void:
	if _motion and _motion.is_valid(): _motion.kill()
	var target := 1.0 if not disabled and (is_hovered() or has_focus()) else 0.0
	if reduced_motion:
		active = target
	else:
		_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_motion.tween_property(self,"active",target,0.18)
	queue_redraw()
func _push(value: float) -> void:
	if _press and _press.is_valid(): _press.kill()
	if reduced_motion:
		depth = value
	else:
		_press = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_press.tween_property(self,"depth",value,0.09)
func _shape(r: Rect2) -> PackedVector2Array:
	var p := r.position
	var e := r.end
	return PackedVector2Array([p,Vector2(e.x-10,p.y),Vector2(e.x,p.y+10),e,Vector2(p.x+10,e.y),Vector2(p.x,e.y-10)])
func _draw() -> void:
	if size.x < 1: return
	if is_instance_valid(portrait_view):
		portrait_view.texture = portrait
		portrait_mask.visible = not compact and portrait != null
		portrait_mask.index = maxi(0,step_index)
		portrait_mask.position = Vector2(43,size.y*0.5-40)
		portrait_mask.size = Vector2(66,80)
	var ink := get_theme_color("ink","Palette")
	var paper := get_theme_color("paper","Palette")
	var gold := get_theme_color("gold","Palette")
	var lift := 0.0 if reduced_motion else active*2.0-depth*2.0
	var r := Rect2(Vector2(1,3-lift),size-Vector2(2,6))
	var color := paper if kind == "step" else (gold if kind == "primary" else get_theme_color("dark","Palette"))
	if kind == "step":
		if active > 0: draw_colored_polygon(_shape(r),Color(1,1,1,active*0.18))
	else:
		color = color.lerp(Color("f9e8c9") if kind == "primary" else Color("506164"),active*0.4)
		if disabled: color = color.lerp(get_theme_color("dark","Palette"),0.65)
		draw_colored_polygon(_shape(r),color)
		var border := _shape(r)
		border.append(border[0])
		draw_polyline(border,Color("e6dece") if not disabled else Color("6e7978"),1.0,true)
	var font := get_theme_font("font","Heading")
	var fs := get_theme_font_size("font_size","Button")
	var fg := ink if kind in ["primary","step"] else paper
	if disabled: fg = Color("adb6b1")
	if kind == "step":
		var cy := size.y*0.5-lift
		var cx := 23.0
		draw_circle(Vector2(cx,cy),15,paper,true,-1,true)
		draw_circle(Vector2(cx,cy),11,gold.darkened(0.25) if selected else Color("757771"),true,-1,true)
		if selected: draw_circle(Vector2(cx,cy),4,paper,true,-1,true)
		var tx := 116.0
		if compact:
			tx = 45.0
		elif portrait:
			pass # Portrait is a masked native TextureRect above the printed paper.
		else:
			draw_rect(Rect2(57,cy-16,31,31),Color("757771"),false,3)
			draw_polyline(PackedVector2Array([Vector2(61,cy-2),Vector2(70,cy+8),Vector2(91,cy-18)]),ink,4,true)
		var lines := text.split("\n")
		for i in lines.size():
			var y := cy+(i-(lines.size()-1)*0.5)*(fs+4)+(font.get_ascent(fs)-font.get_descent(fs))*0.5
			draw_string(font,Vector2(tx,y),lines[i],HORIZONTAL_ALIGNMENT_LEFT,size.x-tx-10,fs,fg)
	else:
		var w := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		draw_string(font,Vector2(maxf(10,(size.x-w)*0.5),(size.y+font.get_ascent(fs)-font.get_descent(fs))*0.5-lift),text,HORIZONTAL_ALIGNMENT_LEFT,size.x-20,fs,fg)
	if has_focus():
		var outline := _shape(r.grow(-3))
		outline.append(outline[0])
		draw_polyline(outline,ink if kind in ["primary","step"] else gold,2.0,true)
