extends "res://scripts/debrief/review_button.gd"
const Portrait = preload("res://scripts/notifications/portrait.gd")
var chosen := 0.0:
	set(value):
		chosen = value
		queue_redraw()
var selection_motion: Tween
var heading: Label
var subtitle: Label
var figure: Control
var glyph: Texture2D
var variant := 0
var caption := ""
func _ready() -> void:
	super._ready()
	var grain := ShaderMaterial.new()
	grain.shader = preload("res://assets/debrief/paper.gdshader")
	material = grain
	text = ""
	figure = Portrait.new()
	figure.variant = variant
	add_child(figure)
	heading = Label.new()
	heading.text = caption
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.max_lines_visible = 2
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_theme_font_override("font",get_theme_font("font","Heading"))
	heading.add_theme_font_size_override("font_size",34)
	heading.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(heading)
	subtitle = Label.new()
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.max_lines_visible = 2
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subtitle.add_theme_font_size_override("font_size",27)
	subtitle.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(subtitle)
	resized.connect(_layout)
	_layout()
func _layout() -> void:
	if not is_instance_valid(figure): return
	var narrow := size.x < 540
	var portrait_width := 170.0 if narrow else 208.0
	var portrait_height := minf(size.y-8,portrait_width*187.0/208.0)
	figure.position = Vector2(36 if narrow else 38,size.y-2-portrait_height)
	figure.size = Vector2(portrait_width,portrait_height)
	var tx := 212.0 if narrow else 248.0
	heading.position = Vector2(tx,28)
	heading.size = Vector2(size.x-tx-42,96)
	heading.add_theme_font_size_override("font_size",29 if narrow else 34)
	subtitle.position = Vector2(tx,28+heading.get_minimum_size().y+8)
	subtitle.size = Vector2(size.x-tx-42,65)
	subtitle.add_theme_font_size_override("font_size",24 if narrow else 27)
func choose(value: bool, immediate := false) -> void:
	selected = value
	if selection_motion and selection_motion.is_valid(): selection_motion.kill()
	if immediate or reduced_motion:
		chosen = float(value)
	else:
		selection_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		selection_motion.tween_property(self,"chosen",float(value),0.24)
func _shape(r: Rect2) -> PackedVector2Array:
	var p := r.position
	var e := r.end
	var c := 18.0
	return PackedVector2Array([p+Vector2(c,0),Vector2(e.x-c,p.y),Vector2(e.x,p.y+c),e-Vector2(0,c),e-Vector2(c,0),Vector2(p.x+c,e.y),Vector2(p.x,e.y-c),p+Vector2(0,c)])
func _draw() -> void:
	var lift := (active*3-depth*2) if not reduced_motion else 0.0
	var r := Rect2(Vector2(2,4-lift),size-Vector2(6,8))
	var ink := get_theme_color("ink","Palette")
	var fill := Color("d2d4c9").lerp(Color("dfb45f"),chosen).lerp(Color("f4e8ca"),active*0.16)
	draw_colored_polygon(_shape(Rect2(r.position+Vector2(0,4),r.size)),Color(0.12,0.18,0.19,0.16))
	draw_colored_polygon(_shape(r),fill)
	var outline := _shape(r)
	outline.append(outline[0])
	draw_polyline(outline,Color("fbf2da") if selected else Color("c4c9bd"),2.5 if selected else 1.0,true)
	if glyph: draw_texture_rect(glyph,Rect2(20,size.y*0.5-20,36,40),false,ink)
	var cx := size.x-32+active*4
	draw_polyline(PackedVector2Array([Vector2(cx-5,size.y*0.5-12),Vector2(cx+4,size.y*0.5),Vector2(cx-5,size.y*0.5+12)]),ink,3,true)
	if has_focus():
		var focus := _shape(r.grow(-6))
		focus.append(focus[0])
		draw_polyline(focus,ink,2,true)
