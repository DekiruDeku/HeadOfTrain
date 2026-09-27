extends Control
var text := ""
var emphasis := 0.0:
	set(value):
		emphasis = value
		queue_redraw()
func _ready() -> void:
	custom_minimum_size.y = 34
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw() -> void:
	if size.x < 24 or size.y < 1: return
	var font := get_theme_font("font","Heading")
	var fs := 23
	while fs > 17 and font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x > size.x-18: fs -= 1
	var w := minf(size.x,font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x+40)
	var col := Color("c8bdab").lerp(get_theme_color("gold","Palette"),emphasis*0.55)
	draw_colored_polygon(PackedVector2Array([Vector2.ZERO,Vector2(w-23,0),Vector2(w,32),Vector2(0,32)]),col)
	draw_line(Vector2(0,32),Vector2(size.x,32),Color("aba99c"),1.2,true)
	draw_string(font,Vector2(9,25),text,HORIZONTAL_ALIGNMENT_LEFT,size.x-18,fs,get_theme_color("ink","Palette"))
