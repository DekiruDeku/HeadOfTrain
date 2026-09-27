extends Control
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw() -> void:
	var ink := Color("9a927c")
	for side in [-1,1]:
		var stem := PackedVector2Array()
		for i in 17:
			var t := float(i)/16
			stem.append(Vector2(size.x/2+side*(size.x*0.25+sin(t*PI*0.5)*size.x*0.20),size.y*(0.94-t*0.86)))
		draw_polyline(stem,ink,1.8,true)
		for i in 6:
			var t := float(i+1)/7
			var p := Vector2(size.x/2+side*(size.x*0.25+sin(t*PI*0.5)*size.x*0.20),size.y*(0.94-t*0.86))
			for direction in [-1,1]:
				var tip := p+Vector2(side*direction*14,-20)
				var middle := (p+tip)/2
				draw_colored_polygon(PackedVector2Array([p,middle+Vector2(4,0),tip,middle-Vector2(4,0)]),ink)
