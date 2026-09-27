extends Control
signal choice_selected(incident_id: String, action_id: String)
signal cancelled
signal retry_requested
const Text = preload("res://scripts/server_text.gd")
const Crew = preload("res://scripts/crew_state.gd")
const Choice = preload("res://scripts/decision/choice_button.gd")
const TITLES := {"luggage-marker":"Чемодан в проходе", "blanket-marker":"Нужен плед", "table-marker":"Уборка столика", "children-marker":"Шум в вагоне", "seat-marker":"Спор о месте"}
const ART := {
	"luggage-marker":preload("res://assets/decisions/luggage.jpg"),
	"blanket-marker":preload("res://assets/decisions/blanket.jpg"),
	"table-marker":preload("res://assets/decisions/table.jpg"),
	"children-marker":preload("res://assets/decisions/children.jpg"),
	"seat-marker":preload("res://assets/decisions/seat.jpg")}
var state: Dictionary = {}
var received_at := 0
var incident_id := ""
var options: Array = []
var choices: Array = []
var scroll_vertical: int:
	get: return scroller.scroll_vertical if is_instance_valid(scroller) else 0
	set(value):
		if is_instance_valid(scroller): scroller.scroll_vertical = value
var reduced_motion := false
var card: PanelContainer
var stage: Control
var scroller: ScrollContainer
var scrim: ColorRect
var content: VBoxContainer
var header: BoxContainer
var heading: VBoxContainer
var timer_box: VBoxContainer
var timer_plate: PanelContainer
var timer_style: StyleBoxFlat
var picture: TextureRect
var copy: VBoxContainer
var option_list: VBoxContainer
var connection_note: Button
var _signature := ""
var _motion: Tween
var _page_tween: Tween
var _layout_motion: Tween
var _rest := Vector2.ZERO
var _compact := false
var _closing := false
var _locked := false
var _choice_ready_at := 0
var _opening := false
var _timer_urgent := false
var _layout_queued := false
var _paper_style: StyleBoxTexture

func _named(node: Node, node_name: String, parent: Node) -> void:
	node.name = node_name
	parent.add_child(node)
	node.owner = self
	node.unique_name_in_owner = true

func _label(node_name: String, parent: Node, font_size: int) -> Label:
	var label := Label.new()
	_named(label,node_name,parent)
	label.add_theme_font_size_override("font_size",font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _ready() -> void:
	clip_contents = true
	scrim = ColorRect.new()
	scrim.color = Color(0.025,0.04,0.047,0.66)
	add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroller = ScrollContainer.new()
	add_child(scroller)
	scroller.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.follow_focus = true
	stage = Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.add_child(stage)
	card = PanelContainer.new()
	stage.add_child(card)
	_paper_style = get_theme_stylebox("panel","PanelContainer").duplicate()
	card.add_theme_stylebox_override("panel",_paper_style)
	var paper_material := ShaderMaterial.new()
	paper_material.shader = preload("res://shaders/decision_paper.gdshader")
	card.material = paper_material
	var shadow := Panel.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.show_behind_parent = true
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color(0,0,0,0)
	shadow_style.shadow_color = Color(0,0,0,0.22)
	shadow_style.shadow_size = 22
	shadow_style.shadow_offset = Vector2(0,12)
	shadow_style.set_corner_radius_all(18)
	shadow.add_theme_stylebox_override("panel",shadow_style)
	card.add_child(shadow)
	shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.size.x = 960
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation",8)
	card.add_child(content)
	header = BoxContainer.new()
	header.add_theme_constant_override("separation",20)
	content.add_child(header)
	heading = VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation",0)
	header.add_child(heading)
	var title := _label("Title",heading,56)
	title.add_theme_font_override("font",preload("res://assets/fonts/Oswald-Bold.ttf"))
	_label("Place",heading,24)
	timer_box = VBoxContainer.new()
	timer_box.custom_minimum_size.x = 232
	timer_box.add_theme_constant_override("separation",5)
	header.add_child(timer_box)
	timer_plate = PanelContainer.new()
	timer_style = StyleBoxFlat.new()
	timer_style.bg_color = get_theme_color("terracotta","Palette")
	timer_style.set_corner_radius_all(3)
	timer_style.content_margin_left = 16
	timer_style.content_margin_right = 16
	timer_plate.add_theme_stylebox_override("panel",timer_style)
	timer_plate.custom_minimum_size.y = 58
	timer_box.add_child(timer_plate)
	var timer_row := HBoxContainer.new()
	timer_row.add_theme_constant_override("separation",12)
	timer_plate.add_child(timer_row)
	var caption := _label("TimerCaption",timer_row,20)
	caption.text = "НА РЕШЕНИЕ"
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color",Color("fff3de"))
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var timer := _label("CriticalTimer",timer_row,38)
	timer.autowrap_mode = TextServer.AUTOWRAP_OFF
	timer.custom_minimum_size.x = 80
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer.add_theme_color_override("font_color",Color("fff3de"))
	var pause := _label("PauseCaption",timer_box,16)
	pause.text = "РЕЙС ПРИОСТАНОВЛЕН"
	pause.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pause.add_theme_color_override("font_color",get_theme_color("muted","Palette"))
	picture = TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.custom_minimum_size.y = 294
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink := ShaderMaterial.new()
	ink.shader = preload("res://shaders/decision_illustration.gdshader")
	picture.material = ink
	content.add_child(picture)
	copy = VBoxContainer.new()
	copy.add_theme_constant_override("separation",8)
	content.add_child(copy)
	_label("Description",copy,24)
	copy.add_child(HSeparator.new())
	var note := _label("Note",copy,21)
	note.add_theme_color_override("font_color",get_theme_color("muted","Palette"))
	var effect := _label("LastEffect",copy,19)
	effect.add_theme_color_override("font_color",get_theme_color("muted","Palette"))
	effect.hide()
	option_list = VBoxContainer.new()
	option_list.add_theme_constant_override("separation",5)
	copy.add_child(option_list)
	for i in 3:
		var button := Choice.new()
		button.number = i+1
		_named(button,"Choice"+str(i+1),option_list)
		button.pressed.connect(_on_choice.bind(i))
		choices.append(button)
	var footer := HBoxContainer.new()
	content.add_child(footer)
	var hint := _label("InputHint",footer,16)
	hint.text = "1–3  ВЫБОР     ↑ ↓  ПЕРЕКЛЮЧЕНИЕ     ENTER  ПОДТВЕРДИТЬ"
	hint.add_theme_color_override("font_color",get_theme_color("muted","Palette"))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var back := Button.new()
	back.text = "Esc · Вернуться к вагону"
	back.custom_minimum_size.y = 30
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.add_theme_font_size_override("font_size",17)
	for key in ["font_color","font_hover_color","font_focus_color","font_pressed_color"]:
		back.add_theme_color_override(key,get_theme_color("muted","Palette"))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0,0,0,0)
	focus.border_color = get_theme_color("ink","Palette")
	focus.set_border_width_all(1)
	back.add_theme_stylebox_override("focus",focus)
	back.add_theme_stylebox_override("hover",focus)
	_named(back,"Cancel",footer)
	back.pressed.connect(_on_cancel)
	connection_note = Button.new()
	connection_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	connection_note.add_theme_color_override("font_color",get_theme_color("terracotta","Palette"))
	connection_note.add_theme_font_size_override("font_size",18)
	connection_note.pressed.connect(func(): retry_requested.emit())
	content.add_child(connection_note)
	connection_note.hide()
	resized.connect(_queue_layout)
	content.minimum_size_changed.connect(_queue_layout)
	visibility_changed.connect(_visibility)
	_queue_layout()

func _queue_layout() -> void:
	if _layout_queued: return
	_layout_queued = true
	_layout.call_deferred()

func _layout() -> void:
	_layout_queued = false
	if not is_instance_valid(card) or size.x < 1: return
	_compact = size.x < 700
	var width := size.x-24 if _compact else 960.0
	var format_changed := header.vertical != _compact or not is_equal_approx(card.size.x,width)
	header.vertical = _compact
	header.add_theme_constant_override("separation",10 if _compact else 20)
	_paper_style.content_margin_left = 16 if _compact else 30
	_paper_style.content_margin_right = 16 if _compact else 30
	card.size.x = width
	timer_box.custom_minimum_size.x = 0 if _compact else 232
	timer_plate.custom_minimum_size.y = 46 if _compact else 58
	%Title.add_theme_font_size_override("font_size",30 if _compact else 56)
	%Place.add_theme_font_size_override("font_size",17 if _compact else 24)
	%Description.add_theme_font_size_override("font_size",18 if _compact else 24)
	%Note.add_theme_font_size_override("font_size",16 if _compact else 21)
	%CriticalTimer.add_theme_font_size_override("font_size",28 if _compact else 38)
	%PauseCaption.visible = not _compact
	%InputHint.visible = not _compact
	%Cancel.custom_minimum_size.y = 44 if _compact else 30
	picture.custom_minimum_size.y = (width-32)/3.0 if _compact else 294.0
	if format_changed:
		for i in options.size():
			if i < choices.size(): _configure_choice(i)
	card.size.y = card.get_combined_minimum_size().y
	var factor := 1.0 if _compact else minf(minf(size.x/1672.0,size.y/941.0),1.2)
	# Keep long server text readable; vertical scrolling handles exceptional content.
	if not _compact: factor = maxf(0.65,factor)
	card.scale = Vector2.ONE*factor
	var rendered := card.size*factor
	stage.custom_minimum_size.y = maxf(size.y,rendered.y+24)
	var previous_rest := _rest
	_rest = Vector2((size.x-rendered.x)*0.5,maxf(12,(size.y-rendered.y)*0.5))
	if not _opening and not _closing and not _rest.is_equal_approx(previous_rest):
		if _layout_motion and _layout_motion.is_valid(): _layout_motion.kill()
		if is_visible_in_tree() and not reduced_motion and not _compact and not format_changed:
			_layout_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_layout_motion.tween_property(card,"position",_rest,0.22)
		else:
			card.position = _rest

func _visibility() -> void:
	if not is_node_ready(): return
	if is_visible_in_tree():
		var config := ConfigFile.new()
		if config.load("user://menu-settings.cfg") == OK:
			reduced_motion = config.get_value("accessibility","reduced_motion",false)
		for button in choices: button.reduced_motion = reduced_motion
		card.modulate.a = 0.0
		scrim.modulate.a = 0.0
		_open.call_deferred()
	else:
		if _motion and _motion.is_valid(): _motion.kill()
		if _page_tween and _page_tween.is_valid(): _page_tween.kill()
		if _layout_motion and _layout_motion.is_valid(): _layout_motion.kill()
		_opening = false
		_closing = false
		copy.modulate.a = 1.0

func _open() -> void:
	# Let wrapped text and containers settle before fixing the landing point.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_visible_in_tree(): return
	if _motion and _motion.is_valid(): _motion.kill()
	if _layout_motion and _layout_motion.is_valid(): _layout_motion.kill()
	_closing = false
	_opening = false
	scroller.scroll_vertical = 0
	_layout()
	card.modulate.a = 1.0
	copy.modulate.a = 1.0
	if reduced_motion:
		card.position = _rest
		scrim.modulate.a = 1.0
		return
	_opening = true
	card.position = Vector2(_rest.x,size.y+36)
	scrim.modulate.a = 0.0
	_motion = create_tween().set_ignore_time_scale(true).set_parallel(true)
	_motion.tween_property(scrim,"modulate:a",1.0,0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_motion.tween_property(card,"position:y",_rest.y-13,0.46).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_motion.chain().tween_property(card,"position:y",_rest.y,0.21).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.chain().tween_callback(func():
		_opening = false
		_layout())

func dismiss() -> void:
	if _closing: return
	_closing = true
	if _motion and _motion.is_valid(): _motion.kill()
	if _layout_motion and _layout_motion.is_valid(): _layout_motion.kill()
	if reduced_motion: return
	_motion = create_tween().set_ignore_time_scale(true).set_parallel(true)
	_motion.tween_property(card,"position:y",size.y+30,0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_motion.tween_property(scrim,"modulate:a",0.0,0.28).set_trans(Tween.TRANS_SINE)
	await _motion.finished

func present(value: Dictionary, incident: Dictionary, _reset_scroll: bool = true) -> void:
	var signature := str(incident.id)+JSON.stringify(value.get("dialog",{}).get("options",[]))+str(value.get("dialog",{}).get("text",""))
	var changed := signature != _signature
	state = value
	received_at = Time.get_ticks_msec()
	incident_id = incident.id
	options = state.get("dialog",{}).get("options",[])
	if changed:
		_choice_ready_at = Time.get_ticks_msec()+220
		if _page_tween and _page_tween.is_valid(): _page_tween.kill()
		_render(incident)
		if is_visible_in_tree() and not _signature.is_empty() and not reduced_motion:
			scroller.scroll_vertical = 0
			copy.modulate.a = 0.25
			_page_tween = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_page_tween.tween_property(copy,"modulate:a",1.0,0.24)
		_signature = signature
	set_locked(false)
	_update_timer()

func _render(incident: Dictionary) -> void:
	var marker := str(incident.get("marker_id",""))
	%Title.text = str(incident.get("title",TITLES.get(marker,"Решение по обращению"))).to_upper()
	%Place.text = "Требуется ваше решение"
	for carriage in state.get("carriages",[]):
		if carriage.id == incident.get("carriage_id"):
			%Place.text = "Вагон "+str(carriage.id).trim_prefix("carriage-")+" · Требуется ваше решение"
	picture.texture = ART.get(marker,ART["luggage-marker"])
	%Description.text = str(state.get("dialog",{}).get("text",incident.get("text","")))
	var staff_name := "Сотрудник на месте"
	for member in state.get("staff",[]):
		if member.get("id") == incident.get("assigned_staff_id"):
			staff_name = str(member.name).split(" ")[0]+" на месте"
	%Note.text = staff_name+". Выберите действие."
	var facts: Dictionary = incident.get("facts",state.get("facts",{}))
	if facts.get(incident_id) is Dictionary: facts = facts[incident_id]
	if marker == "luggage-marker":
		%Note.text = staff_name+". "+(Text.condition(state.get("conditions",{}))+"." if facts.get("conditions_checked",false) else "Место для багажа ещё не проверено.")
	var entry := Crew.latest_entry(state,incident_id)
	%LastEffect.visible = not entry.is_empty()
	if not entry.is_empty():
		%LastEffect.text = str(entry.get("explanation",""))
		var effects: Dictionary = entry.get("effects",{}).duplicate(true)
		effects.erase("facts") # Current facts are already expressed in the situation.
		if not effects.get("loyalty_deltas",{}).is_empty() or effects.has("safety_delta") or not effects.get("critical_marks",[]).is_empty():
			%LastEffect.text += "\n"+Text.effects(effects)
		%LastEffect.tooltip_text = str(entry.get("selected_text",""))+"\n"+Text.effects(entry.get("effects",{}))
	for i in choices.size():
		choices[i].visible = i < options.size()
		choices[i].reset_feedback()
		if i < options.size(): _configure_choice(i)
	_queue_layout()

func _configure_choice(index: int) -> void:
	var option: Dictionary = options[index]
	var reason := str(option.get("unavailable_reason") if option.get("unavailable_reason") != null else "Условия не выполнены")
	choices[index].configure(str(option.text),option.get("available",false),reason,_compact)

func _process(_delta: float) -> void:
	if is_visible_in_tree(): _update_timer()

func _update_timer() -> void:
	if not is_node_ready(): return
	var dialog: Dictionary = state.get("dialog",{}) if state.get("dialog") is Dictionary else {}
	var remaining: Variant = dialog.get("critical_remaining",dialog.get("critical_decision_time"))
	%TimerCaption.text = "НА РЕШЕНИЕ" if remaining != null else "БЕЗ СПЕШКИ"
	%PauseCaption.text = "РЕЙС ПРИОСТАНОВЛЕН" if state.get("paused",false) else "ВЫБЕРИТЕ ДЕЙСТВИЕ"
	var urgent := false
	if remaining == null:
		%CriticalTimer.text = "—"
	else:
		# Display interpolation is bounded by the server's polling horizon.
		var elapsed := minf(float(Time.get_ticks_msec()-received_at)/1000.0,float(state.get("display_horizon",2.0)))
		var seconds := maxf(0.0,float(remaining)-elapsed)
		%CriticalTimer.text = "%d:%02d" % [ceili(seconds)/60,ceili(seconds)%60]
		urgent = seconds <= 8.0
		if seconds <= 0: %PauseCaption.text = "ОЖИДАЕМ ИСХОД"
	if urgent != _timer_urgent:
		_timer_urgent = urgent
		timer_style.bg_color = Color("963423") if urgent else get_theme_color("terracotta","Palette")

func set_locked(locked: bool) -> void:
	_locked = locked
	for i in choices.size():
		choices[i].disabled = locked or i >= options.size() or not options[i].get("available",false)
		choices[i]._refresh()
	if is_node_ready(): %Cancel.disabled = locked

func ensure_control_visible(control: Control) -> void:
	scroller.ensure_control_visible(control)

func set_connection_message(message: String) -> void:
	if not is_instance_valid(connection_note): return
	connection_note.visible = not message.is_empty()
	connection_note.text = "Нет связи. Нажмите, чтобы повторить."
	connection_note.tooltip_text = message

func _on_choice(index: int) -> void:
	if _closing or Time.get_ticks_msec() < _choice_ready_at or index >= options.size() or choices[index].disabled: return
	choices[index].grab_focus()
	choices[index].selected = true
	choices[index].queue_redraw()
	set_locked(true)
	choice_selected.emit(incident_id,options[index].id)

func _on_cancel() -> void:
	if not _locked and not _closing: cancelled.emit()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		_on_cancel()
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_1,KEY_2,KEY_3,KEY_KP_1,KEY_KP_2,KEY_KP_3]:
		var index: int = [KEY_1,KEY_2,KEY_3].find(event.keycode)
		if index < 0: index = [KEY_KP_1,KEY_KP_2,KEY_KP_3].find(event.keycode)
		_on_choice(index)
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_UP,KEY_DOWN,KEY_TAB] and (get_viewport().gui_get_focus_owner() == null or not is_ancestor_of(get_viewport().gui_get_focus_owner())):
		for button in choices:
			if button.visible and not button.disabled:
				button.grab_focus()
				get_viewport().set_input_as_handled()
				break
