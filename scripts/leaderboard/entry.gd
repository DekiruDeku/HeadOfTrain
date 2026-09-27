extends "res://scripts/debrief/review_button.gd"
## The hit area stays still while the printed face reacts to input.
const ART = preload("res://assets/leaderboard/concept-atlas.png")
const FACES = [Rect2(603,366,95,80),Rect2(609,453,86,79),Rect2(602,539,97,87),Rect2(607,633,91,81),Rect2(605,722,93,81)]
var entry: Dictionary = {}
var face := 0
var compact_row := false
func _ready() -> void:
	super._ready()
	clip_contents = true
func _draw() -> void:
	if entry.is_empty(): return
	var ink := Color("202e38")
	var own: bool = entry.get("is_self",false)
	var r := Rect2(Vector2.ZERO,size)
	if own: draw_rect(r,Color("d3af64").lerp(Color("e8c984"),active*0.5))
	elif active > 0: draw_rect(r,Color(0.72,0.58,0.32,active*0.18))
	draw_line(Vector2(0,size.y-1),Vector2(size.x,size.y-1),Color(0.30,0.30,0.25,0.19),1)
	if own: draw_rect(Rect2(0,0,4,size.y),Color("997331"))
	var font := get_theme_font("font","Heading")
	var body_font := get_theme_font("font","Label")
	var shift := (active*3-depth*2) if not reduced_motion else 0.0
	var cy := size.y*0.5
	var rank := str(int(entry.rank))
	var fs := 32 if compact_row else 37
	draw_string(font,Vector2(40-font.get_string_size(rank,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x/2,cy+13),rank,HORIZONTAL_ALIGNMENT_LEFT,80,fs,ink)
	var source: Rect2 = FACES[face % FACES.size()]
	var target := Rect2(115 if not compact_row else 84,cy-42-shift,96,84)
	var points := PackedVector2Array([Vector2(0.18,0),Vector2(0.8,0),Vector2(1,0.2),Vector2(1,1),Vector2(0,1),Vector2(0,0.22)])
	if face == 2:
		# Follow the cutout so the source's gold row is never baked into an avatar.
		points = PackedVector2Array([Vector2(0.32,0),Vector2(0.67,0.02),Vector2(0.85,0.13),Vector2(0.85,0.32),Vector2(0.8,0.67),Vector2(0.79,0.77),Vector2(0.99,1),Vector2(0,1),Vector2(0.24,0.8),Vector2(0.22,0.55),Vector2(0.2,0.28)])
	var uv := PackedVector2Array()
	var positions := PackedVector2Array()
	for p in points:
		positions.append(target.position+p*target.size)
		uv.append((source.position+p*source.size)/Vector2(1672,941))
	draw_polygon(positions,PackedColorArray([Color.WHITE]),uv,ART)
	var x := 250.0 if not compact_row else 192.0
	var points_x := size.x-24
	var name_width := size.x-x-(150 if not compact_row else 115)
	var display := str(entry.display_name)
	var name_size := 30 if not compact_row else 28
	while body_font.get_string_size(display,HORIZONTAL_ALIGNMENT_LEFT,-1,name_size).x > name_width and display.length() > 2:
		display = display.left(display.length()-2).trim_suffix("…")+"…"
	draw_string(body_font,Vector2(x+shift,cy+2),display,HORIZONTAL_ALIGNMENT_LEFT,name_width,name_size,ink)
	var hint := "Вы" if own else ("Учебный участник" if entry.get("is_demo",false) else "Участник")
	draw_string(body_font,Vector2(x+shift,cy+29),hint,HORIZONTAL_ALIGNMENT_LEFT,name_width,19,Color("5b5e53"))
	var score := preload("res://scripts/server_text.gd").metric(entry.total_points)
	var sw := font.get_string_size(score,HORIZONTAL_ALIGNMENT_LEFT,-1,30).x
	draw_string(font,Vector2(points_x-sw,cy+11),score,HORIZONTAL_ALIGNMENT_LEFT,130,30,ink)
	if has_focus(): draw_rect(r.grow(-3),ink,false,2)
