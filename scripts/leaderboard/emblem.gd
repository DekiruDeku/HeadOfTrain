extends Control
const ART = preload("res://assets/leaderboard/concept-atlas.png")
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw() -> void:
	var source := PackedVector2Array([Vector2(172,365),Vector2(306,365),Vector2(305,378),Vector2(283,382),Vector2(284,390),Vector2(319,390),Vector2(331,404),Vector2(310,448),Vector2(275,469),Vector2(258,486),Vector2(258,519),Vector2(283,525),Vector2(287,539),Vector2(291,549),Vector2(199,549),Vector2(201,538),Vector2(211,524),Vector2(231,519),Vector2(231,485),Vector2(207,469),Vector2(176,451),Vector2(156,402),Vector2(165,390),Vector2(191,390),Vector2(187,376)])
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	for p in source:
		points.append((p-Vector2(156,365))/Vector2(175,184)*size)
		uv.append(p/Vector2(1672,941))
	draw_polygon(points,PackedColorArray([Color.WHITE]),uv,ART)
