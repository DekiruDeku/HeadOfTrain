extends Node2D
var stones: Array[Vector3] = []
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 70126
	for i in 1400:
		stones.append(Vector3(rng.randf_range(-2000,2000),rng.randf_range(-108,108),rng.randf_range(1.2,4.2)))

func _process(_delta: float) -> void:
	if is_visible_in_tree(): queue_redraw()

func _draw() -> void:
	# Sleepers and rails pass continuously beneath the stationary train.
	var direction := Vector2(1,-0.363).normalized()
	var across := Vector2(0.36,1).normalized()
	var center := Vector2(850,490)
	draw_line(center-direction*2200,center+direction*2200,Color("686951"),225,true)
	draw_line(center-direction*2200,center+direction*2200,Color("929180"),196,true)
	var ballast_shift := fmod(get_parent().travel*6000,4000)
	for stone in stones:
		var t := fposmod(stone.x+ballast_shift+2000,4000)-2000
		var point := center+direction*t+across*stone.y
		var value := 0.38+stone.z*0.045
		draw_circle(point,stone.z,Color(value,value,value*0.93),true,-1,true)
	var phase := fmod(get_parent().travel*6000,35)
	for i in range(-65,66):
		var p := center + direction * (i*35+phase)
		draw_line(p-across*82,p+across*82,Color("4d5149"),12,true)
	for side in [-1,1]:
		var p: Vector2 = center+across*side*55
		draw_line(p-direction*2200,p+direction*2200,Color("373c37"),9,true)
		draw_line(p-direction*2200-Vector2(0,2),p+direction*2200-Vector2(0,2),Color("c0bcb0"),3,true)
