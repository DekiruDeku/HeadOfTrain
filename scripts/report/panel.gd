extends "res://scripts/debrief/paper_panel.gd"
## All eight clipped corners follow the supplied completion-screen artwork.
func _draw() -> void:
	if size.x < 1 or size.y < 1: return
	if name == "Header":
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO,Vector2(size.x,0),Vector2(size.x-48,size.y),Vector2(0,size.y)]),get_theme_color(palette,"Palette"))
		return
	var c := minf(cut,minf(size.x,size.y)*0.2)
	var p := PackedVector2Array([Vector2(c,0),Vector2(size.x-c,0),Vector2(size.x,c),Vector2(size.x,size.y-c),Vector2(size.x-c,size.y),Vector2(c,size.y),Vector2(0,size.y-c),Vector2(0,c)])
	draw_colored_polygon(p,get_theme_color(palette,"Palette"))
