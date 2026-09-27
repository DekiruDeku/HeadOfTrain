extends Control
var symbol := "shield"
var color := Color("344c3b")
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw() -> void:
	draw_set_transform(Vector2.ZERO,0,size/Vector2(80,80))
	match symbol:
		"shield":
			var p := PackedVector2Array([Vector2(40,3),Vector2(69,14),Vector2(67,42),Vector2(59,59),Vector2(40,76),Vector2(21,59),Vector2(13,42),Vector2(11,14)])
			draw_colored_polygon(p,color)
			draw_polyline(PackedVector2Array([Vector2(40,15),Vector2(56,21),Vector2(54,43),Vector2(40,60),Vector2(40,15)]),(Color("263944") if color.get_luminance() > 0.5 else Color("e8e2d3")),5,true)
		"people", "profile":
			for x in ([16,64,40] if symbol == "people" else [40]):
				var cy := 20.0 if x == 40 else 25.0
				draw_circle(Vector2(x,cy),11 if x == 40 else 9,color,true,-1,true)
				draw_rect(Rect2(x-14,cy+24,28,28),color)
				draw_circle(Vector2(x,cy+24),14,color,true,-1,true)
		"star":
			var points := PackedVector2Array()
			for i in 10:
				var angle := -PI/2+i*PI/5
				points.append(Vector2(40,40)+Vector2(cos(angle),sin(angle))*(38 if i%2 == 0 else 19))
			draw_colored_polygon(points,color)
		"check":
			draw_circle(Vector2(40,40),32,color,true,-1,true)
			draw_polyline(PackedVector2Array([Vector2(23,39),Vector2(35,51),Vector2(58,27)]),Color("ebe6d9"),7,true)
		"warning":
			draw_colored_polygon(PackedVector2Array([Vector2(40,5),Vector2(76,72),Vector2(4,72)]),color)
			draw_line(Vector2(40,25),Vector2(40,48),Color("ebe6d9"),6,true)
			draw_circle(Vector2(40,60),3,Color("ebe6d9"),true,-1,true)
		"repeat":
			draw_arc(Vector2(40,40),25,-PI*0.85,PI*0.1,24,color,8,true)
			draw_arc(Vector2(40,40),25,PI*0.15,PI*1.1,24,color,8,true)
			draw_colored_polygon(PackedVector2Array([Vector2(67,31),Vector2(57,48),Vector2(77,47)]),color)
			draw_colored_polygon(PackedVector2Array([Vector2(13,49),Vector2(23,32),Vector2(3,33)]),color)
		"training":
			draw_line(Vector2(10,40),Vector2(70,40),color,10,true)
			for x in [13,26,54,67]: draw_line(Vector2(x,20),Vector2(x,60),color,8,true)
		_:
			draw_rect(Rect2(14,7,52,67),color)
			for y in [28,43,58]: draw_line(Vector2(26,y),Vector2(54,y),(Color("263944") if color.get_luminance() > 0.5 else Color("e8e2d3")),5,true)
