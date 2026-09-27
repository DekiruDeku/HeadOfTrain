extends "res://scripts/debrief/review_button.gd"
## Stable full-card target; only its printed border responds to hover and focus.
func _draw() -> void:
	var r := Rect2(Vector2(3,3),size-Vector2(6,6))
	var p := _shape(r)
	if active > 0.001:
		draw_colored_polygon(p,Color(1,1,1,active*0.09))
		p.append(p[0])
		draw_polyline(p,Color(0.64,0.46,0.20,active*0.7),2.0,true)
	if has_focus():
		var outline := _shape(r.grow(-4))
		outline.append(outline[0])
		draw_polyline(outline,get_theme_color("ink","Palette"),3,true)
