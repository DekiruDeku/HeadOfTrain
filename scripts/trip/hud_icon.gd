extends Control
var kind := "train"
var ink := Color("e9e4d5")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shape = StyleBoxFlat.new()
	shape.bg_color = ink
	shape.set_corner_radius_all(4)

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, size / 64.0)
	match kind:
		"train":
			draw_style_box(_box(ink), Rect2(4, 20, 56, 26))
			for x in [11, 23, 35, 47]:
				draw_rect(Rect2(x, 25, 8, 10), Color("183342"))
			draw_line(Vector2(6, 39), Vector2(58, 39), Color("b95839"), 3)
			for x in [16, 48]:
				draw_circle(Vector2(x, 49), 4, ink)
		"case":
			draw_rect(Rect2(13, 19, 39, 38), ink)
			draw_rect(Rect2(25, 9, 16, 12), ink, false, 4)
			for x in [20, 44]:
				draw_line(Vector2(x, 20), Vector2(x, 56), Color("eed8a9"), 3)
				draw_circle(Vector2(x, 59), 3, ink)
		"blanket":
			draw_style_box(_box(ink), Rect2(11, 10, 42, 47))
			for y in [21, 33, 45]:
				draw_rect(Rect2(11, y, 42, 5), Color("a9c8d6"))
		"clean":
			draw_style_box(_box(ink), Rect2(21, 30, 28, 29))
			draw_rect(Rect2(27, 18, 16, 18), ink)
			draw_rect(Rect2(20, 12, 30, 9), ink)
			for i in 3:
				draw_line(Vector2(16, 17), Vector2(5, 7+i*10), ink, 2)
		"person":
			draw_circle(Vector2(32, 19), 10, ink)
			draw_style_box(_box(ink), Rect2(14, 33, 36, 22))
		"shield":
			draw_colored_polygon(PackedVector2Array([Vector2(10,12),Vector2(32,5),Vector2(54,12),Vector2(51,37),Vector2(32,58),Vector2(13,37)]), ink)
			draw_polyline(PackedVector2Array([Vector2(22,30),Vector2(30,38),Vector2(43,22)]),Color("183342"),4,true)
		"pause":
			draw_rect(Rect2(19,16,9,32),ink)
			draw_rect(Rect2(37,16,9,32),ink)
		"play", "fast", "faster":
			var count: int = {"play":1,"fast":2,"faster":3}[kind]
			for i in count:
				var x := 32.0 - count*8.0 + i*16.0
				draw_colored_polygon(PackedVector2Array([Vector2(x,18),Vector2(x+15,32),Vector2(x,46)]),ink)
		"clock":
			draw_arc(Vector2(32,34),22,0,TAU,40,ink,4,true)
			draw_line(Vector2(32,34),Vector2(32,20),ink,3)
			draw_line(Vector2(32,34),Vector2(44,38),ink,3)
			draw_rect(Rect2(24,3,16,5),ink)
		"lock":
			draw_arc(Vector2(32,24),12,PI,TAU,20,ink,5,true)
			draw_style_box(_box(ink),Rect2(15,25,34,29))
		"cap":
			draw_colored_polygon(PackedVector2Array([Vector2(5,23),Vector2(30,8),Vector2(58,18),Vector2(53,34),Vector2(13,37)]),ink)
			draw_line(Vector2(13,36),Vector2(53,32),Color("426077"),5,true)
			draw_arc(Vector2(33,32),19,0.2,2.9,20,ink,9,true)
		"gear":
			for i in 8:
				var p := Vector2.from_angle(i*TAU/8.0)
				draw_line(Vector2(32,32)+p*16,Vector2(32,32)+p*27,ink,9,true)
			draw_circle(Vector2(32,32),21,ink)
			draw_circle(Vector2(32,32),9,Color("183342"))
		"chevron":
			draw_polyline(PackedVector2Array([Vector2(24,16),Vector2(40,32),Vector2(24,48)]),ink,5,true)

var shape: StyleBoxFlat
func _box(color: Color) -> StyleBoxFlat:
	if shape == null:
		shape = StyleBoxFlat.new()
		shape.bg_color = color
		shape.set_corner_radius_all(4)
	return shape
