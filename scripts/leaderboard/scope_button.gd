extends "res://scripts/debrief/review_button.gd"
func _draw() -> void:
	var ink := Color("23303a")
	if active > 0: draw_rect(Rect2(Vector2.ZERO,size),Color(1,1,1,active*0.2))
	var font := get_theme_font("font","Heading")
	var fs := 30
	var w := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	draw_string(font,Vector2((size.x-w)/2,(size.y+font.get_ascent(fs)-font.get_descent(fs))/2+depth*2),text,HORIZONTAL_ALIGNMENT_LEFT,size.x,fs,ink)
	if selected: draw_rect(Rect2(size.x*0.28,size.y-5,size.x*0.44,3),ink)
	if has_focus(): draw_rect(Rect2(Vector2(3,3),size-Vector2(6,6)),ink,false,2)
