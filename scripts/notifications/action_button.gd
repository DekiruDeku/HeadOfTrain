extends "res://scripts/debrief/review_button.gd"
func _draw() -> void:
	if not disabled:
		super._draw()
		return
	var r := Rect2(Vector2(1,3),size-Vector2(2,6))
	draw_colored_polygon(_shape(r),Color("c9c8bc"))
	var font := get_theme_font("font","Heading")
	var fs := get_theme_font_size("font_size","Button")
	var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	var x := (size.x-width)*0.5+18
	var ink := Color("73766d")
	draw_texture_rect(preload("res://assets/menu/lock.svg"),Rect2(x-46,size.y*0.5-19,34,38),false,ink)
	draw_string(font,Vector2(x,(size.y+font.get_ascent(fs)-font.get_descent(fs))*0.5),text,HORIZONTAL_ALIGNMENT_LEFT,size.x-x-12,fs,ink)
