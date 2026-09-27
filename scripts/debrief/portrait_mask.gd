extends Control
## Native vector clip around the three portrait silhouettes in the supplied concept.
var index := 0
func _ready() -> void:
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw() -> void:
	var outlines := [
		[Vector2(.19,.16),Vector2(.40,.05),Vector2(.83,.08),Vector2(.86,.22),Vector2(.91,.43),Vector2(.81,.66),Vector2(.97,.96),Vector2(.02,.96),Vector2(.22,.70),Vector2(.21,.48),Vector2(.16,.38)],
		[Vector2(.16,.34),Vector2(.23,.09),Vector2(.58,.02),Vector2(.85,.06),Vector2(.88,.22),Vector2(.99,.23),Vector2(.95,.37),Vector2(.82,.43),Vector2(.85,.61),Vector2(.71,.75),Vector2(.96,.97),Vector2(.01,.97),Vector2(.17,.73),Vector2(.06,.69),Vector2(.02,.55),Vector2(.12,.42)],
		[Vector2(.27,.12),Vector2(.52,.02),Vector2(.73,.08),Vector2(.88,.21),Vector2(.89,.45),Vector2(.97,.68),Vector2(.78,.80),Vector2(.99,.98),Vector2(.01,.98),Vector2(.22,.76),Vector2(.06,.69),Vector2(.08,.48),Vector2(.18,.31)]
	]
	var points := PackedVector2Array()
	for p in outlines[clampi(index,0,2)]: points.append(p*size)
	draw_colored_polygon(points,Color.WHITE)
