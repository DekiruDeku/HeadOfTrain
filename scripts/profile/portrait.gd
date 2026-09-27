extends Control
## Sample only the illustrated silhouette from the supplied concept atlas.
const ART = preload("res://assets/profile/concept-atlas.png")
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw() -> void:
	var source := PackedVector2Array([Vector2(73,506),Vector2(73,429),Vector2(122,397),Vector2(115,359),Vector2(99,325),Vector2(95,287),Vector2(103,273),Vector2(94,232),Vector2(112,191),Vector2(148,158),Vector2(178,140),Vector2(226,127),Vector2(251,126),Vector2(276,143),Vector2(287,162),Vector2(309,180),Vector2(314,227),Vector2(308,264),Vector2(320,283),Vector2(317,319),Vector2(298,352),Vector2(291,402),Vector2(347,442),Vector2(367,458),Vector2(387,506)])
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	for p in source:
		points.append((p-Vector2(73,122))/Vector2(314,384)*size)
		uv.append(p/Vector2(1672,941))
	draw_polygon(points,PackedColorArray([Color.WHITE]),uv,ART)
