extends PanelContainer
## Cut paper edges belong to the panel; content is still laid out by containers.
@export var palette := "paper"
@export var cut := 20.0
func _ready() -> void:
	var grain := ShaderMaterial.new()
	grain.shader = preload("res://assets/debrief/paper.gdshader")
	material = grain
	resized.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_PASS
func _draw() -> void:
	var c := minf(cut,minf(size.x,size.y)*0.2)
	var p := PackedVector2Array([Vector2.ZERO,Vector2(size.x-c,0),Vector2(size.x,c),size,Vector2(c,size.y),Vector2(0,size.y-c)])
	draw_colored_polygon(p,get_theme_color(palette,"Palette"))
