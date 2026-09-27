extends Control
## UV silhouettes sample illustration only; all text and interactions are native.
const ART = preload("res://assets/notifications/concept-atlas.png")
var variant := 0
const OUTLINES = [
	[Vector2(76,357),Vector2(101,317),Vector2(144,291),Vector2(141,280),Vector2(118,273),Vector2(110,252),Vector2(122,228),Vector2(129,207),Vector2(147,183),Vector2(170,172),Vector2(215,171),Vector2(237,183),Vector2(247,202),Vector2(239,225),Vector2(230,260),Vector2(220,289),Vector2(252,299),Vector2(265,319),Vector2(273,357)],
	[Vector2(70,554),Vector2(84,517),Vector2(125,495),Vector2(137,477),Vector2(129,456),Vector2(120,433),Vector2(124,408),Vector2(146,387),Vector2(181,377),Vector2(207,384),Vector2(222,402),Vector2(224,434),Vector2(210,461),Vector2(229,472),Vector2(239,500),Vector2(263,519),Vector2(276,554)],
	[Vector2(88,754),Vector2(112,716),Vector2(145,699),Vector2(141,686),Vector2(120,678),Vector2(115,652),Vector2(131,621),Vector2(138,595),Vector2(162,578),Vector2(195,572),Vector2(218,577),Vector2(236,598),Vector2(245,624),Vector2(245,651),Vector2(252,667),Vector2(236,686),Vector2(234,705),Vector2(263,715),Vector2(276,754)]
]
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw() -> void:
	var origin: Vector2 = [Vector2(70,170),Vector2(70,377),Vector2(70,571)][variant]
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	for p: Vector2 in OUTLINES[variant]:
		points.append((p-origin)/Vector2(208,187)*size)
		uv.append(p/Vector2(1672,941))
	draw_polygon(points,PackedColorArray([Color.WHITE]),uv,ART)
