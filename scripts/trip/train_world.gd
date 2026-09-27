extends Control
signal request_selected(id: String)
const Crew = preload("res://scripts/crew_state.gd")
const ButtonFX = preload("res://scripts/trip/hud_button.gd")
const Icon = preload("res://scripts/trip/hud_icon.gd")
const STEP := Vector2(1306, -628)
const TRAIN_SCALE := Vector2(1.06, 0.80)
const ORIGIN := Vector2(235, -76)
const OUTLINE := [Vector2(26,680),Vector2(46,652),Vector2(119,619),Vector2(357,473),Vector2(827,239),Vector2(1317,14),Vector2(1350,9),Vector2(1381,32),Vector2(1403,19),Vector2(1489,111),Vector2(1508,162),Vector2(1505,268),Vector2(1487,351),Vector2(1457,386),Vector2(354,935),Vector2(201,982),Vector2(158,949),Vector2(108,906),Vector2(29,756)]
var rig: Node2D
var bodies: Array[Node2D] = []
var markers: Array[Button] = []
var people: Dictionary = {}
var state: Dictionary = {}
var camera_tween: Tween
var focused_carriage := "carriage-1"
var selected_id := ""
var reduced_motion := false
var travel := 0.0
var speed := 1.0
var landscape: ShaderMaterial
var point_positions := {
	"c1-entry":Vector2(375,760),"c1-desk":Vector2(435,702),"c1-aisle":Vector2(670,595),"c1-blanket":Vector2(1000,443),"c1-luggage":Vector2(880,503),"c1-connector":Vector2(1410,257),"c1-door":Vector2(1420,255),
	"c2-door":Vector2(323,750),"c2-connector":Vector2(323,750),"c2-aisle":Vector2(705,577),"c2-luggage":Vector2(880,494),"c2-table":Vector2(1090,397),"c2-exit":Vector2(1390,270),"c2-desk":Vector2(1370,267)}
var pulse := 0.0
var marker_clock := 0.0
var luggage_prop: Node2D
const SEAT_CUSHIONS := [Vector2(526,579),Vector2(762,468),Vector2(1093,300),Vector2(1198,251),Vector2(854,549),Vector2(1078,435)]
const PASSENGER_HIPS := [Vector2(193,292),Vector2(176,306),Vector2(154,310),Vector2(190,292),Vector2(198,298),Vector2(162,318)]

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := TextureRect.new()
	bg.texture = preload("res://assets/trip/forest.png")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	landscape = ShaderMaterial.new()
	landscape.shader = preload("res://assets/trip/landscape.gdshader")
	bg.material = landscape
	add_child(bg)
	var tracks := Node2D.new()
	tracks.set_script(preload("res://scripts/trip/tracks.gd"))
	add_child(tracks)
	rig = Node2D.new()
	rig.name = "CameraRig"
	add_child(rig)
	# All cars remain in one continuous world; focus is a camera translation.
	for i in range(-1, 3):
		var car := Node2D.new()
		car.name = "Carriage" + str(i + 1)
		car.position = ORIGIN + STEP * TRAIN_SCALE * i
		car.scale = TRAIN_SCALE
		rig.add_child(car)
		bodies.append(car)
		var texture: Texture2D = preload("res://assets/trip/standard-clean.png")
		var shadow := Polygon2D.new()
		shadow.polygon = PackedVector2Array(OUTLINE)
		shadow.position = Vector2(13, 30)
		shadow.color = Color(0.05,0.09,0.07,0.3)
		car.add_child(shadow)
		var shell := Sprite2D.new()
		shell.texture = texture
		shell.centered = false
		car.add_child(shell)
		if i in [0, 1]:
			_populate(car, i)
	for i in 3:
		var person := staff_visual(i)
		person.scale = Vector2(0.155, 0.135)
		rig.add_child(person)
		people[Crew.STAFF[i]] = person

static func staff_visual(index: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = preload("res://assets/trip/staff-clean.png")
	sprite.region_enabled = true
	sprite.region_rect = Rect2(index*384,0,384,1024)
	sprite.offset = Vector2(0,-512)
	return sprite

func _populate(car: Node2D, index: int) -> void:
	for n in SEAT_CUSHIONS.size():
		var passenger := Sprite2D.new()
		passenger.texture = preload("res://assets/trip/seated-clean.png")
		passenger.region_enabled = true
		var slot := (n + index * 2) % 6
		passenger.name = "Passenger"+str(n+1)
		passenger.region_rect = Rect2(Vector2(slot % 3 * 512 + 100, slot / 3 * 512 + 10), Vector2(350,490))
		passenger.centered = false
		passenger.offset = -PASSENGER_HIPS[slot]
		passenger.position = SEAT_CUSHIONS[n]
		passenger.scale = Vector2(0.235,0.245)
		passenger.z_index = 1
		passenger.set_meta("seat_anchor",SEAT_CUSHIONS[n])
		passenger.set_meta("variant",slot)
		car.add_child(passenger)
	# Suitcase is a spatial interactive object, attached to the luggage route point.
	if index == 1:
		luggage_prop = preload("res://scripts/trip/luggage_prop.gd").new()
		luggage_prop.name = "LuggageInAisle"
		luggage_prop.position = point_positions["c2-luggage"]+Vector2(48,-22)
		car.add_child(luggage_prop)

func bind_state(value: Dictionary) -> void:
	if state.get("trip_id") != value.get("trip_id"):
		for marker in markers: marker.queue_free()
		markers.clear()
	state = value
	if is_instance_valid(luggage_prop):
		luggage_prop.visible = not state.get("facts",{}).get("luggage-1",{}).get("aisle_clear",state.get("facts",{}).get("aisle_clear",false))
	speed = 0.0 if state.get("paused", false) or state.get("status") == "completed" else float(state.get("time_speed",1))
	_refresh_markers()

func _refresh_markers() -> void:
	# Retain controls by incident identity across polls so pointer/focus/tweens survive.
	for incident in state.get("incidents", []):
		var marker: Button
		for existing in markers:
			if existing.get_meta("request_id") == incident.id:
				marker = existing
		if marker == null:
			marker = ButtonFX.new()
			marker.name = "Marker_" + incident.id
			marker.set_meta("request_id", incident.id)
			marker.size = Vector2(76, 48)
			marker.add_theme_font_override("font", preload("res://assets/fonts/Oswald-Bold.ttf"))
			marker.add_theme_font_size_override("font_size", 25)
			marker.pressed.connect(func(): request_selected.emit(str(marker.get_meta("request_id"))))
			var tip := Polygon2D.new()
			tip.name = "Tip"
			tip.polygon = PackedVector2Array([Vector2(25,47),Vector2(38,64),Vector2(50,47)])
			marker.add_child(tip)
			rig.add_child(marker)
			markers.append(marker)
			marker.modulate.a = 0
			marker.create_tween().tween_property(marker,"modulate:a",1.0,0.25)
		var old_state: String = marker.get_meta("state", "")
		if old_state != "" and old_state != "completed" and incident.state == "completed" and Crew.status_key(incident) == "resolved" and not reduced_motion:
			_success_particles(_point(incident.get("route_point_id","c1-luggage")))
		marker.set_meta("state", incident.state)
		marker.visible = incident.state != "completed"
		marker.set_meta("incident",incident)
		marker.tooltip_text = incident.text + "\n" + Crew.status_text(incident)
		marker.accessibility_name = marker.tooltip_text
		marker.reduced_motion = reduced_motion
		var color := Color("da8a28") if incident.type == "safety" else Color("32749d")
		if incident.state == "resolving":
			color = Color("688947")
		if incident.get("reaction_remaining") != null and float(incident.reaction_remaining) < 15 and incident.state in ["waiting","en_route"]:
			color = Color("bb4d39")
		if marker.get_meta("color",Color.TRANSPARENT) != color or marker.get_meta("selected",false) != (incident.id == selected_id):
			marker.set_meta("color",color)
			marker.set_meta("selected",incident.id == selected_id)
			var style := StyleBoxFlat.new()
			style.bg_color = color
			style.border_color = Color("fff3cd") if incident.id == selected_id else Color("f3ecdb")
			style.set_border_width_all(3 if incident.id == selected_id else 2)
			style.set_corner_radius_all(5)
			style.shadow_color = Color(0,0,0,0.25)
			style.shadow_size = 5
			for key in ["normal","hover","pressed"]:
				marker.add_theme_stylebox_override(key,style)
			marker.get_node("Tip").color = color

func focus_carriage(id: String) -> void:
	if id.is_empty(): id = "carriage-1"
	if focused_carriage == id: return
	focused_carriage = id
	if camera_tween and camera_tween.is_valid(): camera_tween.kill()
	var target := -STEP * TRAIN_SCALE * (1 if id == "carriage-2" else 0)
	if reduced_motion:
		rig.position = target
	else:
		camera_tween = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		camera_tween.tween_property(rig,"position",target,0.95)

func select_request(id: String) -> void:
	selected_id = id
	_refresh_markers()

func set_locked(value: bool) -> void:
	for marker in markers:
		marker.disabled = value

func _point(id: String) -> Vector2:
	return ORIGIN + (point_positions.get(id,Vector2(700,550)) + STEP * (1 if id.begins_with("c2") else 0)) * TRAIN_SCALE

func show_time(simulation_time: float) -> void:
	var elapsed := maxf(0, simulation_time - float(state.get("simulation_time", 0)))
	for incident in state.get("incidents", []):
		for marker in markers:
			if marker.get_meta("request_id") != incident.id: continue
			var seconds: Variant = incident.get("reaction_remaining")
			if incident.state == "resolving":
				seconds = incident.get("service_remaining") if incident.type == "service" else incident.get("critical_decision_time")
			marker.text = Crew.seconds(float(seconds)-elapsed).trim_prefix("0") if seconds != null else "···"
			var target := _point(incident.get("route_point_id","c1-luggage"))
			var offset := Vector2(-38,-165)
			if incident.marker_id == "children-marker": offset.x += 86
			if incident.marker_id == "seat-marker": offset.x += 86
			marker.position = target + offset
			if incident.id == selected_id and not reduced_motion:
				marker.position.y += sin(pulse*2.5)*3
	for member in state.get("staff", []):
		var person: Sprite2D = people[Crew.visual_staff(member.id)]
		var feet := _point(member.route_point_id)
		if member.state == "moving":
			var route: Array = member.route
			feet = _point(route.back().route_point_id)
			for i in range(1, route.size()):
				if simulation_time <= float(route[i].at):
					var progress := clampf((simulation_time-float(route[i-1].at))/(float(route[i].at)-float(route[i-1].at)),0,1)
					feet = _point(route[i-1].route_point_id).lerp(_point(route[i].route_point_id),progress)
					break
		if member.state == "moving" and speed > 0 and not reduced_motion:
			feet.y += sin(pulse*12)*1.6
		person.position = feet
		person.visible = true

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	pulse += delta * speed
	if not reduced_motion:
		travel += delta * speed * 0.021
		landscape.set_shader_parameter("travel", travel)


func _success_particles(at: Vector2) -> void:
	var particles := GPUParticles2D.new()
	particles.emitting = false
	particles.amount = 10
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = 0.7
	particles.position = at - Vector2(0,110)
	particles.visibility_rect = Rect2(-90,-90,180,180)
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0,-1,0)
	material.spread = 70
	material.initial_velocity_min = 35
	material.initial_velocity_max = 65
	material.gravity = Vector3(0,55,0)
	material.scale_min = 2.0
	material.scale_max = 3.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color("e5cf8c"),Color(0.7,0.88,0.5,0)])
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	material.color_ramp = ramp_texture
	particles.process_material = material
	rig.add_child(particles)
	particles.finished.connect(particles.queue_free)
	particles.restart()
