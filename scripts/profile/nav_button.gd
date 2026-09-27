extends "res://scripts/debrief/review_button.gd"
var glyph: Texture2D
func _draw() -> void:
	var gold := get_theme_color("gold","Palette")
	var selected_tab := kind == "primary"
	if selected_tab: draw_rect(Rect2(Vector2.ZERO,size),Color("78613b").lerp(gold,active*0.2))
	elif active > 0.001: draw_rect(Rect2(Vector2.ZERO,size),Color(1,1,1,active*0.09))
	if selected_tab: draw_rect(Rect2(0,size.y-3,size.x,3),gold)
	var color := Color("f3d58c") if selected_tab else Color("bdc3c0").lerp(Color("f8f0dd"),active)
	var font := get_theme_font("font","Heading")
	var fs := get_theme_font_size("font_size","Button")
	var tx := 60.0 if glyph and size.x > 180 else 0.0
	if tx > 0: draw_texture_rect(glyph,Rect2(21,size.y*0.5-16,32,32),false,color)
	draw_string(font,Vector2(tx+(size.x-tx-font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x)/2,(size.y+font.get_ascent(fs)-font.get_descent(fs))/2),text,HORIZONTAL_ALIGNMENT_LEFT,size.x-tx,fs,color)
	if has_focus(): draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),gold,false,2)
