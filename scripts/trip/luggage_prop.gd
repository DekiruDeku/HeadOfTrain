extends Node2D
## A small brown suitcase in the aisle, anchored at its contact with the floor.
func _draw() -> void:
	_draw_shadow(Vector2(0,3),Vector2(21,7),Color(0,0,0,0.18))
	draw_colored_polygon(PackedVector2Array([Vector2(-17,-34),Vector2(11,-39),Vector2(20,-30),Vector2(20,3),Vector2(-9,10),Vector2(-17,2)]),Color("684d38"))
	draw_colored_polygon(PackedVector2Array([Vector2(-17,-34),Vector2(11,-39),Vector2(11,-3),Vector2(-17,3)]),Color("a37b52"))
	draw_polyline(PackedVector2Array([Vector2(-7,-36),Vector2(-7,-47),Vector2(5,-49),Vector2(5,-38)]),Color("d5c8aa"),3,true)
	for x in [-10,5]: draw_line(Vector2(x,-34),Vector2(x,1),Color("51412f"),2,true)
	draw_circle(Vector2(-9,7),3,Color("303536"))
	draw_circle(Vector2(15,3),3,Color("303536"))
func _draw_shadow(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 24: points.append(center+Vector2(cos(i*TAU/24),sin(i*TAU/24))*radius)
	draw_colored_polygon(points,color)

