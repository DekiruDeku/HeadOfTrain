extends Control
signal request_selected(request_id: String)
signal assignment_requested(incident_id: String, staff_id: String)
signal time_speed_requested(speed: int)
signal retry_requested
signal back_requested
const Crew = preload("res://scripts/crew_state.gd")
const World = preload("res://scripts/trip/train_world.gd")
const ButtonFX = preload("res://scripts/trip/hud_button.gd")
const Icon = preload("res://scripts/trip/hud_icon.gd")
const DESIGN := Vector2(1672,941)
const INK := Color("102d3d")
const PAPER := Color("eae4d5")
const GOLD := Color("ffc15a")
const BLUE := Color("357aa6")
const GREEN := Color("96ba69")
const RED := Color("b63b2a")
const TITLES := {"luggage-marker":"Чемодан в проходе","blanket-marker":"Нужен плед","table-marker":"Уборка столика","children-marker":"Шум в вагоне","seat-marker":"Спор о месте"}
const SEATS := {"luggage-marker":"18","blanket-marker":"06","table-marker":"24","children-marker":"12","seat-marker":"28"}
var state: Dictionary = {}
var requests: Array = []
var selected_id := ""
var selected_staff := ""
var focused_carriage := "carriage-1"
var locked := false
var page := 0
var received_at := 0
var scroll_vertical := 0 # Compatibility with the application's screen-navigation API.
var reduced_motion := false
var design: Control
var carriage: Control
var rows: Array = []
var cards: Array = []
var carriage_buttons: Array[Button] = []
var speed_buttons: Array[Button] = []
var labels: Dictionary = {}
var bars: Dictionary = {}
var route_progress: ProgressBar
var route_train: Control
var modal: Control
var detail: Control
var elapsed_tick := 0.0
var previous_focus: Control
var _modal_tween: Tween
var _metric_tweens: Dictionary = {}
var duration := 360.0
var request_panel: Panel
var displayed_requests: Array = []

func _ready() -> void:
	theme = preload("res://theme/trip_theme.tres")
	clip_contents = true
	_build()
	resized.connect(_adapt_layout)
	visibility_changed.connect(_visibility)
	_adapt_layout()

func _visibility() -> void:
	if not is_node_ready(): return
	var config := ConfigFile.new()
	if config.load("user://menu-settings.cfg") == OK:
		reduced_motion = config.get_value("accessibility","reduced_motion",false)
	carriage.reduced_motion = reduced_motion
	for node in design.find_children("*","Button",true,false):
		if node.get_script() == ButtonFX: node.reduced_motion = reduced_motion
	if is_visible_in_tree():
		if get_viewport().gui_get_focus_owner() == null:
			carriage_buttons[0 if focused_carriage == "carriage-1" else 1].grab_focus()
	else:
		modal.hide()

func _adapt_layout() -> void:
	if not is_instance_valid(design): return
	var factor := minf(size.x/DESIGN.x,size.y/DESIGN.y)
	design.scale = Vector2.ONE * factor
	design.position = (size-DESIGN*factor)*0.5

func _control(parent: Node, pos: Vector2, dimensions: Vector2) -> Control:
	var node := Control.new()
	node.position = pos
	node.size = dimensions
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _label(parent: Node, value: String, pos: Vector2, dimensions: Vector2, font_size := 22, color := PAPER, heading := false) -> Label:
	var node := Label.new()
	node.text = value
	node.position = pos
	node.size = dimensions
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_constant_override("outline_size",0)
	node.add_theme_color_override("font_color",color)
	if heading: node.add_theme_font_override("font",preload("res://assets/fonts/Oswald-Bold.ttf"))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _icon(parent: Node, kind: String, pos: Vector2, dimensions: Vector2, color := PAPER) -> Control:
	var node := Icon.new()
	node.kind = kind
	node.ink = color
	node.position = pos
	node.size = dimensions
	parent.add_child(node)
	return node

func _button(parent: Node, value: String, pos: Vector2, dimensions: Vector2, callback: Callable, paper := false) -> Button:
	var node := ButtonFX.new()
	node.position = pos
	node.size = dimensions
	node.text = value
	if paper: node.theme_type_variation = &"PaperButton"
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

func _panel(parent: Node, pos: Vector2, dimensions: Vector2, color: Color, radius := 0) -> Panel:
	var node := Panel.new()
	node.position = pos
	node.size = dimensions
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	node.add_theme_stylebox_override("panel",style)
	parent.add_child(node)
	return node

func _bar(parent: Node, pos: Vector2, dimensions: Vector2, color: Color) -> ProgressBar:
	var node := ProgressBar.new()
	node.position = pos
	node.size = dimensions
	node.show_percentage = false
	node.add_theme_font_size_override("font_size",1)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("0c2635")
	bg.border_color = Color("415660")
	bg.set_border_width_all(0 if dimensions.y < 6 else 1)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	node.add_theme_stylebox_override("background",bg)
	node.add_theme_stylebox_override("fill",fill)
	node.custom_minimum_size = dimensions
	parent.add_child(node)
	return node

func _build() -> void:
	_panel(self,Vector2.ZERO,Vector2(4000,4000),INK)
	design = _control(self,Vector2.ZERO,DESIGN)
	design.name = "Design"
	carriage = World.new()
	carriage.position = Vector2(0,80)
	carriage.size = Vector2(1672,642)
	design.add_child(carriage)
	carriage.request_selected.connect(_on_request_selected)
	_build_header()
	_build_requests()
	var titleplate := _panel(design,Vector2(350,97),Vector2(350,102),Color(0.91,0.88,0.78,0.85),9)
	labels.carriage = _label(titleplate,"ВАГОН 1 · СТАНДАРТ",Vector2(25,10),Vector2(310,43),27,INK,true)
	_icon(titleplate,"person",Vector2(25,58),Vector2(26,26),Color("345465"))
	labels.passengers = _label(titleplate,"24 пассажира",Vector2(62,56),Vector2(270,30),21,Color("345465"))
	_build_footer()
	_build_detail()
	_build_modal()
	labels.connection = _button(design,"",Vector2(500,95),Vector2(720,56),func(): retry_requested.emit())
	labels.connection.visible = false

func _build_header() -> void:
	_panel(design,Vector2.ZERO,Vector2(1672,80),INK)
	_icon(design,"cap",Vector2(24,12),Vector2(52,52))
	_label(design,"МОСКВА",Vector2(466,14),Vector2(120,42),27,PAPER,true)
	_label(design,"САНКТ-ПЕТЕРБУРГ",Vector2(930,14),Vector2(251,42),27,PAPER,true)
	route_progress = _bar(design,Vector2(595,32),Vector2(310,24),GOLD)
	route_progress.scale.y = 0.15
	for i in 7:
		var dot := _panel(design,Vector2(590+i*53,29),Vector2(9,9),GOLD if i<3 else Color("638292"),5)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	route_train = _icon(design,"train",Vector2(605,5),Vector2(48,40))
	_label(design,"ДО ПРИБЫТИЯ",Vector2(697,48),Vector2(132,26),17)
	labels.time = _label(design,"06:00",Vector2(833,44),Vector2(85,32),25,PAPER,true)
	for i in 2:
		var x := 1195+i*239
		var panel := _button(design,"",Vector2(x,10),Vector2(224,56),func(): pass)
		panel.focus_mode = Control.FOCUS_NONE
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon(panel,"person" if i == 0 else "shield",Vector2(12,12),Vector2(33,33))
		_label(panel,"ЛОЯЛЬНОСТЬ" if i == 0 else "БЕЗОПАСНОСТЬ",Vector2(54,5),Vector2(145,23),18,PAPER,true)
		var key := "loyalty" if i == 0 else "safety"
		labels[key] = _label(panel,"—",Vector2(187,3),Vector2(36,28),23,PAPER,true)
		bars[key] = _bar(panel,Vector2(54,35),Vector2(155,22),GREEN)
		bars[key].scale.y = 0.48

func _build_requests() -> void:
	var panel := _panel(design,Vector2(10,98),Vector2(316,450),Color("e4dfd0"),12)
	request_panel = panel
	_label(panel,"ОБРАЩЕНИЯ",Vector2(20,7),Vector2(250,46),30,INK,true)
	var badge := _panel(panel,Vector2(263,14),Vector2(32,32),RED,16)
	labels.count = _label(badge,"0",Vector2.ZERO,Vector2(32,32),23,PAPER,true)
	labels.count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for i in 3:
		var row := _button(panel,"",Vector2(10,60+i*115),Vector2(296,107),_select_row.bind(i),true)
		row.toggle_mode = true
		var stripe := _panel(row,Vector2(6,12),Vector2(3,82),BLUE)
		var icon := _icon(row,"case",Vector2(17,23),Vector2(46,54),Color("91632b"))
		var title := _label(row,"",Vector2(76,8),Vector2(205,30),22,INK,true)
		title.clip_text = true
		var place := _label(row,"",Vector2(76,41),Vector2(210,24),19,Color("687071"))
		var timer := _label(row,"",Vector2(96,72),Vector2(78,29),23,BLUE,true)
		var clock := _icon(row,"clock",Vector2(76,76),Vector2(19,20),BLUE)
		var status := _label(row,"",Vector2(175,76),Vector2(117,24),17,INK)
		rows.append({"button":row,"title":title,"place":place,"timer":timer,"status":status,"icon":icon,"stripe":stripe,"clock":clock})
	labels.empty = _label(panel,"Все обращения решены.\nМожно немного выдохнуть.",Vector2(20,74),Vector2(280,110),23,INK)
	labels.empty.visible = false
	labels.prev = _button(panel,"‹",Vector2(10,409),Vector2(46,32),func(): page-=1; _render_requests(),true)
	labels.page = _label(panel,"1 / 1",Vector2(100,412),Vector2(115,28),18,Color("5e6a6c"))
	labels.page.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	labels.next = _button(panel,"›",Vector2(260,409),Vector2(46,32),func(): page+=1; _render_requests(),true)

func _build_footer() -> void:
	var footer := _panel(design,Vector2(0,722),Vector2(1672,219),INK)
	_label(footer,"БРИГАДА",Vector2(28,8),Vector2(260,35),25,PAPER,true)
	for i in 3:
		var card := _button(footer,"",Vector2(27+i*265,48),Vector2(252,111),_on_staff_selected.bind(i))
		card.toggle_mode = true
		var portrait := _control(card,Vector2(1,1),Vector2(98,108))
		portrait.clip_contents = true
		var figure := World.staff_visual(i)
		figure.scale = Vector2(0.30,0.30)
		figure.position = Vector2(51,303)
		portrait.add_child(figure)
		var name_label := _label(card,["АННА","БОРИС","ВЕРА"][i],Vector2(108,18),Vector2(140,28),22,PAPER,true)
		var dot := _panel(card,Vector2(108,62),Vector2(12,12),GREEN,6)
		var status := _label(card,"Свободен",Vector2(126,54),Vector2(125,29),17,GREEN)
		var eta := _label(card,"",Vector2(108,82),Vector2(140,22),15,Color("b4c4c8"))
		cards.append({"button":card,"name":name_label,"dot":dot,"status":status,"eta":eta})
	_label(footer,"Выберите обращение, затем свободного сотрудника",Vector2(28,176),Vector2(756,25),18,Color("a5b8be"))
	for x in [822,1253,1569]: _panel(footer,Vector2(x,17),Vector2(1,146),Color("49606c"))
	_label(footer,"СОСТАВ ПОЕЗДА",Vector2(848,12),Vector2(380,30),20)
	for i in 3:
		var button := _button(footer,"",Vector2(849+i*127,55),Vector2(118,111),_on_carriage_selected.bind("carriage-"+str(i+1)))
		button.toggle_mode = true
		button.disabled = i == 2
		button.tooltip_text = "Вагон откроется в следующих рейсах" if i == 2 else "Перейти в вагон " + str(i+1)
		_icon(button,"train",Vector2(17,0),Vector2(84,53),GOLD if i == 0 else Color("9daeb1") if i == 1 else Color("48616d"))
		_label(button,"0"+str(i+1),Vector2(45,50),Vector2(45,30),24,PAPER if i<2 else Color("81939b"),true)
		var type_label := _label(button,"СТАНДАРТ" if i<2 else "КОМФОРТ",Vector2(1,82),Vector2(116,25),18,PAPER if i<2 else Color("81939b"))
		type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i == 2: _icon(button,"lock",Vector2(17,55),Vector2(20,22),Color("81939b"))
		carriage_buttons.append(button)
	_label(footer,"СКОРОСТЬ ВРЕМЕНИ",Vector2(1280,12),Vector2(270,30),20)
	for i in 4:
		var speed: int = [0,1,2,4][i]
		var button := _button(footer,"",Vector2(1280+i*66,62),Vector2(58,65),_on_speed.bind(speed))
		button.toggle_mode = true
		button.tooltip_text = ["Пауза · пробел","Обычная скорость · 1","Ускорение ×2 · 2","Ускорение ×4 · 4"][i]
		_icon(button,["pause","play","fast","faster"][i],Vector2(4,8),Vector2(50,50))
		speed_buttons.append(button)
	labels.speed = _label(footer,"Обычная скорость",Vector2(1280,143),Vector2(270,26),17,Color("c2cdd0"))
	var menu := _button(footer,"",Vector2(1583,55),Vector2(73,100),show_menu)
	menu.name = "MenuButton"
	menu.add_theme_stylebox_override("normal",preload("res://theme/menu_empty_panel.tres"))
	_icon(menu,"gear",Vector2(16,13),Vector2(42,42),Color("9dafb5"))
	_label(menu,"МЕНЮ",Vector2(12,66),Vector2(62,28),19,Color("a5b8be"))

func _build_detail() -> void:
	detail = _panel(design,Vector2(350,629),Vector2(890,76),Color(0.05,0.15,0.20,0.95),8)
	detail.visible = false
	labels.detail = _label(detail,"",Vector2(18,10),Vector2(650,29),21,PAPER,true)
	labels.hint = _label(detail,"",Vector2(18,41),Vector2(650,26),18,Color("bed0d4"))
	labels.action = _button(detail,"Открыть диалог",Vector2(672,15),Vector2(202,46),_on_open_dialog)

func _build_modal() -> void:
	modal = _control(design,Vector2.ZERO,DESIGN)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel(modal,Vector2.ZERO,DESIGN,Color(0.02,0.07,0.11,0.73))
	var panel := _panel(modal,Vector2(601,252),Vector2(470,400),INK,12)
	_label(panel,"УПРАВЛЕНИЕ РЕЙСОМ",Vector2(32,25),Vector2(405,48),31,PAPER,true)
	labels.menu_state = _label(panel,"",Vector2(32,82),Vector2(405,53),21,Color("bdcdd0"))
	labels.resume = _button(panel,"Продолжить рейс",Vector2(32,153),Vector2(406,57),hide_menu)
	_button(panel,"Пауза / продолжить",Vector2(32,224),Vector2(406,57),func(): _on_speed(1 if state.get("time_speed",1)==0 else 0))
	_button(panel,"К отправлению",Vector2(32,295),Vector2(406,57),func(): hide_menu(); back_requested.emit())
	modal.visible = false
	var buttons := modal.find_children("*", "Button", true, false)
	for i in buttons.size():
		buttons[i].focus_next = buttons[(i+1)%buttons.size()].get_path()
		buttons[i].focus_previous = buttons[(i-1+buttons.size())%buttons.size()].get_path()
		buttons[i].focus_neighbor_bottom = buttons[i].focus_next
		buttons[i].focus_neighbor_top = buttons[i].focus_previous

func show_menu() -> void:
	previous_focus = get_viewport().gui_get_focus_owner()
	modal.show()
	labels.menu_state.text = "Рейс на паузе" if state.get("paused",false) else "Рейс продолжается. Пауза — кнопкой ниже."
	labels.resume.grab_focus()
	if _modal_tween and _modal_tween.is_valid(): _modal_tween.kill()
	modal.modulate.a = 0.0 if not reduced_motion else 1.0
	_modal_tween = create_tween().set_ignore_time_scale(true)
	_modal_tween.tween_property(modal,"modulate:a",1.0,0.18)

func hide_menu() -> void:
	if _modal_tween and _modal_tween.is_valid(): _modal_tween.kill()
	modal.hide()
	if is_instance_valid(previous_focus): previous_focus.grab_focus()

func show_trip(value: Dictionary) -> void:
	if not is_node_ready(): return
	if state.get("trip_id") != value.trip_id:
		selected_id = str(value.incidents[0].id) if not value.incidents.is_empty() else ""
		selected_staff = ""
		page = 0
		duration = float(value.get("simulation_time",0)) + float(value.get("remaining_time",360))
		focused_carriage = str(value.incidents[0].carriage_id) if not value.incidents.is_empty() else "carriage-1"
		carriage.focus_carriage(focused_carriage)
	state = value
	received_at = Time.get_ticks_msec()
	requests = state.incidents
	carriage.bind_state(state)
	carriage.select_request(selected_id)
	var loyalty: Variant = state.scales.get("overall_loyalty")
	# The report metric is null until an incident completes. In-flight display
	# uses the server-provided passenger scores, never an invented starting value.
	if loyalty == null and not state.scales.get("loyalty",{}).is_empty():
		var total := 0.0
		for amount in state.scales.loyalty.values(): total += float(amount)
		loyalty = total/state.scales.loyalty.size()
		labels.loyalty.tooltip_text = "Средняя текущая лояльность пассажиров"
	_set_metric("loyalty", loyalty)
	_set_metric("safety", state.scales.get("safety"))
	_render_requests()
	_update_display()
	set_locked(locked)

func _set_metric(key: String, value: Variant) -> void:
	labels[key].text = "—" if value == null else str(roundi(float(value)))
	var target := 0.0 if value == null else float(value)
	if is_equal_approx(bars[key].value,target): return
	if _metric_tweens.has(key) and _metric_tweens[key].is_valid(): _metric_tweens[key].kill()
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(bars[key],"value",target,0.01 if reduced_motion else 0.4)
	_metric_tweens[key] = tween

func _elapsed() -> float:
	if state.get("paused",false) or state.get("status") == "completed": return 0.0
	var age := float(Time.get_ticks_msec()-received_at)/1000.0
	return minf(age*float(state.get("time_speed",1)),float(state.get("display_horizon",2.0)))

func _process(delta: float) -> void:
	if state.is_empty() or not is_visible_in_tree(): return
	carriage.show_time(float(state.get("simulation_time",0))+_elapsed())
	elapsed_tick += delta
	if elapsed_tick >= 0.1:
		elapsed_tick = 0.0
		_update_display()

func _render_requests() -> void:
	displayed_requests = []
	for item in requests:
		if item.state != "completed": displayed_requests.append(item)
	var pages := maxi(1,ceili(displayed_requests.size()/3.0))
	page = clampi(page,0,pages-1)
	labels.count.text = str(displayed_requests.size())
	labels.page.text = "%s / %s" % [page+1,pages]
	labels.prev.disabled = page == 0
	labels.next.disabled = page == pages-1
	labels.empty.visible = displayed_requests.is_empty()
	var panel_height := 105.0+maxi(1,mini(displayed_requests.size()-page*3,3))*115.0
	request_panel.size.y = panel_height
	labels.prev.position.y = panel_height-41
	labels.next.position.y = panel_height-41
	labels.page.position.y = panel_height-39
	for i in 3:
		rows[i].button.visible = i+page*3 < displayed_requests.size()
	_update_request_times()

func _update_request_times() -> void:
	for i in 3:
		if i+page*3 >= displayed_requests.size(): continue
		var incident: Dictionary = displayed_requests[i+page*3]
		var row: Dictionary = rows[i]
		row.button.set_pressed_no_signal(incident.id == selected_id)
		row.title.text = TITLES.get(incident.marker_id,incident.text)
		row.place.text = "Вагон %s · место %s" % [incident.carriage_id.trim_prefix("carriage-"),SEATS.get(incident.marker_id,"—")]
		row.status.text = {"waiting":"Ожидает","en_route":"В пути","resolving":"В работе"}.get(incident.state,"Завершено")
		var remaining: Variant = incident.get("reaction_remaining")
		if incident.state == "resolving":
			remaining = incident.get("service_remaining") if incident.type == "service" else incident.get("critical_decision_time")
		row.timer.text = Crew.seconds(float(remaining)-_elapsed()).trim_prefix("0") if remaining != null else "···"
		var color := RED if incident.type == "safety" else BLUE
		if incident.state == "resolving": color = Color("638944")
		row.timer.add_theme_color_override("font_color",color)
		row.clock.ink = color
		row.clock.queue_redraw()
		row.icon.shape.bg_color = Color("926126") if incident.type == "safety" else BLUE
		row.stripe.get_theme_stylebox("panel").bg_color = color
		row.icon.kind = {"luggage-marker":"case","blanket-marker":"blanket","table-marker":"clean"}.get(incident.marker_id,"person")
		row.icon.ink = Color("926126") if incident.type == "safety" else BLUE
		row.icon.queue_redraw()
		row.button.tooltip_text = incident.text + "\n" + Crew.priority_text(incident)
		row.button.accessibility_name = row.title.text+". "+row.place.text+". "+row.status.text

func _update_display() -> void:
	if state.is_empty(): return
	var elapsed := _elapsed()
	var sim := float(state.get("simulation_time",0))+elapsed
	labels.time.text = Crew.seconds(float(state.get("remaining_time",0))-elapsed)
	route_progress.value = clampf(sim/maxf(duration,1)*100,0,100)
	route_train.position.x = 581+route_progress.value/100*308
	var selected := _selected_request()
	detail.visible = not selected.is_empty()
	if not selected.is_empty():
		labels.detail.text = TITLES.get(selected.marker_id,selected.text)+" · "+Crew.status_text(selected)
		labels.hint.text = "Выберите свободного сотрудника в бригаде" if selected.state == "waiting" else "Сотрудник направляется к пассажиру" if selected.state == "en_route" else "Обслуживание завершится автоматически" if selected.type == "service" else "Сотрудник на месте — примите решение"
		labels.action.visible = selected.state == "resolving" and selected.type != "service"
		if selected.state == "completed":
			labels.hint.text = "Обращение завершено"
			labels.action.visible = false
	_update_request_times()
	for i in 3:
		var members: Array = state.get("staff",[])
		if i >= members.size(): cards[i].button.hide(); continue
		var member: Dictionary = members[i]
		var card: Dictionary = cards[i]
		card.name.text = str(member.name).to_upper()
		var color := GREEN if member.state == "free" else BLUE if member.state == "moving" else GOLD
		card.status.text = {"free":"Свободен","moving":"В пути","serving":"Выполняет"}[member.state]
		card.status.add_theme_color_override("font_color",color)
		card.dot.get_theme_stylebox("panel").bg_color = color
		if member.state == "moving":
			card.eta.text = Crew.seconds(float(member.arrival_time)-sim)+" · до прибытия"
		elif member.state == "serving" and member.get("service_end_time") != null:
			card.eta.text = Crew.seconds(float(member.service_end_time)-sim)+" · осталось"
		else:
			var eta: Variant = Crew.eta(state,member.id,selected_id)
			card.eta.text = "Назначить · "+Crew.seconds(eta) if eta != null and not selected.is_empty() and selected.state == "waiting" else "Вагон "+member.carriage_id.trim_prefix("carriage-")
		card.button.set_pressed_no_signal(member.id == selected_staff)
		card.button.tooltip_text = member.name+" · "+card.status.text+"\n"+card.eta.text
	for i in 3:
		carriage_buttons[i].set_pressed_no_signal(focused_carriage == "carriage-"+str(i+1))
		var icon = carriage_buttons[i].get_child(0)
		icon.ink = GOLD if carriage_buttons[i].button_pressed else Color("9daeb1") if i<2 else Color("48616d")
		icon.shape.bg_color = icon.ink
		icon.queue_redraw()
	labels.carriage.text = "ВАГОН %s · СТАНДАРТ" % focused_carriage.trim_prefix("carriage-")
	labels.passengers.text = "6 пассажиров · 2 + 2"
	var rate := int(state.get("time_speed",1))
	for i in 4: speed_buttons[i].set_pressed_no_signal([0,1,2,4][i] == rate)
	labels.speed.text = "Рейс завершён" if state.get("status") == "completed" else "Пауза" if state.get("paused",false) else "Обычная скорость" if rate == 1 else "Ускорение ×"+str(rate)
	if modal.visible: labels.menu_state.text = "Рейс на паузе" if state.get("paused",false) else "Рейс продолжается. Пауза — кнопкой ниже."

func _selected_request() -> Dictionary:
	for incident in requests:
		if incident.id == selected_id: return incident
	return {}

func _select_row(index: int) -> void:
	if index+page*3 < displayed_requests.size(): _on_request_selected(displayed_requests[index+page*3].id)

func _on_request_selected(id: String) -> void:
	if locked: return
	if not Crew.enabled(state): request_selected.emit(id); return
	var focus := get_viewport().gui_get_focus_owner()
	if focus: focus.release_focus()
	selected_id = id
	var incident := _selected_request()
	if not incident.is_empty():
		_on_carriage_selected(incident.carriage_id)
		var index := displayed_requests.find(incident)
		if index >= 0: page = index/3
	carriage.select_request(id)
	_render_requests()
	_update_display()

func _on_carriage_selected(id: String) -> void:
	var available := false
	for car in state.get("carriages",[]):
		if car.id == id and car.get("available",true): available = true
	if not available: return
	focused_carriage = id
	carriage.focus_carriage(id)
	_update_display()

func _on_staff_selected(index: int) -> void:
	if locked or index >= state.get("staff",[]).size(): return
	var member: Dictionary = state.staff[index]
	selected_staff = member.id
	var selected := _selected_request()
	if not selected.is_empty() and selected.state == "waiting" and member.state == "free" and Crew.eta(state,member.id,selected_id) != null:
		assignment_requested.emit(selected_id,member.id)
	_update_display()

func _on_open_dialog() -> void:
	if not locked: request_selected.emit(selected_id)

func _on_speed(value: int) -> void:
	if not locked and state.get("status") == "in_progress": time_speed_requested.emit(value)

func set_locked(value: bool) -> void:
	locked = value
	for row in rows: row.button.disabled = value
	for card in cards: card.button.disabled = value
	carriage.set_locked(value)
	labels.action.disabled = value
	for button in speed_buttons: button.disabled = value or state.get("simulation_mode") != "full_b4" or state.get("status") == "completed"

func set_connection_message(message: String) -> void:
	labels.connection.visible = not message.is_empty()
	labels.connection.text = "Нет связи · нажмите, чтобы восстановить"
	labels.connection.tooltip_text = message
	if not message.is_empty(): carriage.speed = 0.0

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	if modal.visible and event.keycode != KEY_ESCAPE: return
	match event.keycode:
		KEY_ESCAPE:
			if modal.visible: hide_menu()
			else: show_menu()
		KEY_SPACE: _on_speed(1 if state.get("time_speed",1) == 0 else 0)
		KEY_1: _on_speed(1)
		KEY_2: _on_speed(2)
		KEY_4: _on_speed(4)
		KEY_A: _on_carriage_selected("carriage-1")
		KEY_D: _on_carriage_selected("carriage-2")
		_: return
	get_viewport().set_input_as_handled()
