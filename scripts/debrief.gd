extends Control
signal back_requested
signal continue_requested
signal report_requested
const Text = preload("res://scripts/server_text.gd")
const Progress = preload("res://scripts/progress_data.gd")
const Paper = preload("res://scripts/debrief/paper_panel.gd")
const ReviewButton = preload("res://scripts/debrief/review_button.gd")
const SectionHeader = preload("res://scripts/debrief/section_header.gd")
const ATLAS = preload("res://assets/debrief/concept-atlas.png")
const TITLES := {"luggage":"Чемодан в проходе","blanket":"Нужен плед","table":"Уборка столика","children":"Шум в вагоне","seat":"Спор о месте"}
const SITUATIONS := {
	"luggage":"Пассажир оставил чемодан в проходе и хочет держать багаж рядом с собой.",
	"blanket":"Пассажиру прохладно. Он попросил принести плед.",
	"table":"Пассажир попросил убрать использованную посуду со столика.",
	"children":"Шум мешает соседнему пассажиру. Нужно учесть интересы семьи и остальных людей в вагоне.",
	"seat":"Место пассажира занято. Нужно проверить билеты и помочь разобраться без конфликта."}
const ART := {
	"luggage":preload("res://assets/debrief/luggage.jpg"),
	"blanket":preload("res://assets/debrief/blanket.jpg"),
	"table":preload("res://assets/debrief/table.jpg"),
	"children":preload("res://assets/debrief/children.jpg"),
	"seat":preload("res://assets/debrief/seat.jpg")}
var history: Array = []
var page := 0
var final_report := false
var saved_report: Dictionary = {}
var context: Dictionary = {}
var reduced_motion := false
var selected_step := 1
var scroll_vertical: int:
	get: return scroller.scroll_vertical if is_instance_valid(scroller) else 0
	set(value):
		if is_instance_valid(scroller): scroller.scroll_vertical = value
var scroller: ScrollContainer
var canvas: Control
var layout: VBoxContainer
var header: BoxContainer
var body: BoxContainer
var footer: BoxContainer
var sidebar: PanelContainer
var side_content: VBoxContainer
var steps_box: BoxContainer
var step_track: Control
var highlight: Polygon2D
var rail: Line2D
var steps: Array = []
var sections: Array = []
var section_headers: Array = []
var illustration: PanelContainer
var picture: TextureRect
var picture_clip: Control
var picture_open: Button
var old_picture: TextureRect
var detail: PanelContainer
var detail_scroll: ScrollContainer
var detail_copy: VBoxContainer
var footer_tip: VBoxContainer
var footer_actions: BoxContainer
var selector: OptionButton
var badges: BoxContainer
var loyalty_badge: PanelContainer
var result_badge: PanelContainer
var modal: Control
var modal_picture: TextureRect
var modal_close: Button
var previous_focus: Control
var _entry_motion: Tween
var _page_motion: Tween
var _step_motion: Tween
var _scroll_motion: Tween
var _art_motion: Tween
var _modal_motion: Tween
var _compact := false
var _layout_queued := false
var _locked := false

func _named(node: Node, title: String, parent: Node) -> void:
	node.name = title
	parent.add_child(node)
	node.owner = self
	node.unique_name_in_owner = true

func _label(title: String, parent: Node, fs := 23, heading := false) -> Label:
	var label := Label.new()
	_named(label,title,parent)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",fs)
	if heading: label.add_theme_font_override("font",get_theme_font("font","Heading"))
	return label

func _button(title: String, value: String, parent: Node, callback: Callable, kind := "secondary") -> Button:
	var b := ReviewButton.new()
	b.kind = kind
	b.text = value
	b.custom_minimum_size = Vector2(48,52)
	_named(b,title,parent)
	b.pressed.connect(callback)
	return b

func _atlas(rect: Rect2) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = ATLAS
	tex.region = rect
	return tex

func _paper(parent: Node, title: String, palette := "paper", pad := 22) -> PanelContainer:
	var p := Paper.new()
	p.palette = palette
	_named(p,title,parent)
	var style := get_theme_stylebox("panel","PanelContainer").duplicate()
	style.content_margin_left = pad
	style.content_margin_right = pad
	style.content_margin_top = pad
	style.content_margin_bottom = pad
	p.add_theme_stylebox_override("panel",style)
	return p

func _ready() -> void:
	clip_contents = true
	var background := ColorRect.new()
	background.color = get_theme_color("background","Palette")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroller = ScrollContainer.new()
	add_child(scroller)
	scroller.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.follow_focus = true
	canvas = Control.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.add_child(canvas)
	layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation",8)
	canvas.add_child(layout)
	_build_header()
	_build_body()
	_build_footer()
	_build_modal()
	resized.connect(_queue_layout)
	layout.minimum_size_changed.connect(_queue_layout)
	steps_box.sort_children.connect(func(): _update_track.call_deferred())
	visibility_changed.connect(_visibility)
	_adapt_layout()
	_render_page()

func _build_header() -> void:
	var plate := _paper(layout,"HeaderPlate","dark",12)
	var header_style := plate.get_theme_stylebox("panel").duplicate()
	header_style.content_margin_left = 28
	header_style.content_margin_right = 28
	plate.add_theme_stylebox_override("panel",header_style)
	plate.cut = 0
	header = BoxContainer.new()
	header.add_theme_constant_override("separation",28)
	plate.add_child(header)
	var title := _label("Title",header,46,true)
	title.text = "РАЗБОР РЕШЕНИЯ"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var divider := ColorRect.new()
	divider.name = "Divider"
	divider.color = get_theme_color("paper","Palette")
	divider.custom_minimum_size.x = 1
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(divider)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(heading)
	_label("SituationTitle",heading,30,true)
	# A quiet piece of the original landscape, with no baked UI text.
	var landscape := TextureRect.new()
	landscape.texture = _atlas(Rect2(985,0,687,103))
	landscape.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	landscape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	landscape.custom_minimum_size = Vector2(220,0)
	landscape.modulate.a = 0.55
	landscape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_named(landscape,"Landscape",header)
	for label in [title,%SituationTitle]: label.add_theme_color_override("font_color",get_theme_color("paper","Palette"))

func _build_body() -> void:
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left",10)
	margin.add_theme_constant_override("margin_right",10)
	layout.add_child(margin)
	body = BoxContainer.new()
	body.add_theme_constant_override("separation",10)
	margin.add_child(body)
	sidebar = _paper(body,"Sidebar","paper",16)
	sidebar.custom_minimum_size.x = 280
	side_content = VBoxContainer.new()
	side_content.add_theme_constant_override("separation",12)
	sidebar.add_child(side_content)
	step_track = Control.new()
	step_track.custom_minimum_size.y = 340
	step_track.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_content.add_child(step_track)
	rail = Line2D.new()
	rail.width = 3
	rail.default_color = Color("747972")
	step_track.add_child(rail)
	highlight = Polygon2D.new()
	highlight.color = get_theme_color("gold","Palette")
	step_track.add_child(highlight)
	steps_box = BoxContainer.new()
	steps_box.vertical = true
	steps_box.add_theme_constant_override("separation",4)
	step_track.add_child(steps_box)
	steps_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var portraits := [_atlas(Rect2(95,168,81,96)),_atlas(Rect2(88,301,96,113)),_atlas(Rect2(93,448,86,112))]
	for i in 4:
		var b := _button("Step"+str(i),["Обращение","Ваше\nрешение","Реакция","Результат"][i],steps_box,_select_step.bind(i),"step")
		b.step_index = i
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.portrait = portraits[i] if i < 3 else null
		b.accessibility_name = ["Обращение","Ваше решение","Реакция","Результат"][i]
		steps.append(b)
	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation",8)
	side_content.add_child(pager)
	_button("Previous","‹",pager,_on_previous)
	var count := _label("PageLabel",pager,18)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button("Next","›",pager,_on_next)
	%Previous.accessibility_name = "Предыдущее решение"
	%Next.accessibility_name = "Следующее решение"
	selector = OptionButton.new()
	selector.custom_minimum_size.y = 36
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.fit_to_longest_item = false
	selector.add_theme_font_size_override("font_size",17)
	for color in ["font_color","font_hover_color","font_focus_color","font_pressed_color"]:
		selector.add_theme_color_override(color,get_theme_color("ink","Palette"))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0,0,0,0)
	focus.border_color = get_theme_color("ink","Palette")
	focus.set_border_width_all(2)
	selector.add_theme_stylebox_override("focus",focus)
	selector.item_selected.connect(_choose_incident)
	selector.tooltip_text = "Перейти к другой ситуации"
	side_content.add_child(selector)
	illustration = _paper(body,"Illustration","paper",8)
	illustration.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	illustration.size_flags_stretch_ratio = 0.94
	picture_clip = Control.new()
	picture_clip.clip_contents = true
	illustration.add_child(picture_clip)
	picture = _picture(picture_clip)
	old_picture = _picture(picture_clip)
	old_picture.hide()
	picture_open = Button.new()
	picture_open.text = ""
	picture_open.tooltip_text = "Рассмотреть иллюстрацию"
	picture_open.accessibility_name = "Открыть иллюстрацию крупно"
	picture_open.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	picture_clip.add_child(picture_open)
	picture_open.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture_open.pressed.connect(_open_art)
	picture_open.mouse_entered.connect(_art_hover.bind(true))
	picture_open.mouse_exited.connect(_art_hover.bind(false))
	picture_open.focus_entered.connect(_art_hover.bind(true))
	picture_open.focus_exited.connect(_art_hover.bind(false))
	var art_focus := StyleBoxFlat.new()
	art_focus.bg_color = Color(0,0,0,0)
	art_focus.border_color = get_theme_color("gold","Palette")
	art_focus.set_border_width_all(3)
	picture_open.add_theme_stylebox_override("focus",art_focus)
	var hint := _label("ArtHint",picture_open,15)
	hint.text = "РАССМОТРЕТЬ  +"
	hint.add_theme_color_override("font_color",Color("ffefd1"))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -32
	hint.offset_left = 12
	hint.offset_right = -12
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var hint_plate := StyleBoxFlat.new()
	hint_plate.bg_color = Color(0.10,0.15,0.17,0.75)
	hint_plate.content_margin_left = 8
	hint_plate.content_margin_right = 8
	hint.add_theme_stylebox_override("normal",hint_plate)
	detail = _paper(body,"Detail")
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_stretch_ratio = 1.06
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.follow_focus = true
	var detail_layout := VBoxContainer.new()
	detail_layout.add_theme_constant_override("separation",14)
	detail.add_child(detail_layout)
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_layout.add_child(detail_scroll)
	detail_copy = VBoxContainer.new()
	detail_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_copy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_copy.add_theme_constant_override("separation",10)
	detail_scroll.add_child(detail_copy)
	for i in 4:
		var section := VBoxContainer.new()
		section.size_flags_vertical = Control.SIZE_EXPAND_FILL
		section.add_theme_constant_override("separation",4)
		detail_copy.add_child(section)
		var h := SectionHeader.new()
		h.text = ["СИТУАЦИЯ","ВАШЕ ДЕЙСТВИЕ","ЧТО ПРОИЗОШЛО","ПОЧЕМУ ЭТО СРАБОТАЛО"][i]
		section.add_child(h)
		section_headers.append(h)
		_label(["Situation","Choice","Effect","Explanation"][i],section,20)
		if i == 1:
			var service_choice := _label("ServiceChoice",section,20)
			service_choice.hide()
		sections.append(section)
	badges = BoxContainer.new()
	badges.add_theme_constant_override("separation",12)
	detail_layout.add_child(badges)
	loyalty_badge = _paper(badges,"LoyaltyBadge","sage",10)
	loyalty_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var loyalty := _label("Loyalty",loyalty_badge,22,true)
	loyalty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loyalty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loyalty_badge.custom_minimum_size.y = 60
	result_badge = _paper(badges,"ResultBadge","sage",10)
	result_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var result := _label("Result",result_badge,22,true)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Keep raw provenance available without competing with the lesson.
	var evidence := _label("Evidence",detail_copy,16)
	evidence.visible = false
	for n in ["Summary","Facts","Persistence","TripId"]:
		var extra := _label(n,detail_copy,16)
		extra.hide()

func _picture(parent: Node) -> TextureRect:
	var p := TextureRect.new()
	p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return p

func _build_footer() -> void:
	var plate := _paper(layout,"FooterPlate","dark",14)
	plate.custom_minimum_size.y = 104
	plate.cut = 0
	footer = BoxContainer.new()
	footer.add_theme_constant_override("separation",24)
	plate.add_child(footer)
	var portrait := TextureRect.new()
	portrait.texture = _atlas(Rect2(51,800,117,121))
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(88,72)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_named(portrait,"Mentor",footer)
	footer_tip = VBoxContainer.new()
	footer_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_tip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer_tip.add_theme_constant_override("separation",4)
	footer.add_child(footer_tip)
	var caption := _label("RecommendationTitle",footer_tip,20,true)
	caption.text = "РЕКОМЕНДАЦИЯ"
	caption.add_theme_color_override("font_color",get_theme_color("gold","Palette"))
	var tip := _label("Recommendation",footer_tip,21)
	tip.add_theme_color_override("font_color",get_theme_color("paper","Palette"))
	footer_actions = BoxContainer.new()
	footer_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer_actions.add_theme_constant_override("separation",16)
	footer.add_child(footer_actions)
	var c := _button("Continue","К НОВОЙ ТРЕНИРОВКЕ",footer_actions,_on_continue,"primary")
	c.custom_minimum_size = Vector2(248,58)
	var b := _button("Back","К ОТЧЁТУ",footer_actions,_on_back)
	b.custom_minimum_size = Vector2(168,58)

func _build_modal() -> void:
	modal = Control.new()
	add_child(modal)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = Color(0.055,0.08,0.09,0.96)
	modal.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: _close_art())
	modal_picture = _picture(modal)
	modal_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	modal_picture.offset_left = 24
	modal_picture.offset_right = -24
	modal_picture.offset_top = 24
	modal_picture.offset_bottom = -82
	modal_close = _button("CloseArt","ЗАКРЫТЬ  ×",modal,_close_art)
	modal_close.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	modal_close.offset_left = -100
	modal_close.offset_right = 100
	modal_close.offset_top = -68
	modal_close.offset_bottom = -16
	modal_close.focus_neighbor_left = modal_close.get_path()
	modal_close.focus_neighbor_right = modal_close.get_path()
	modal_close.focus_neighbor_top = modal_close.get_path()
	modal_close.focus_neighbor_bottom = modal_close.get_path()
	modal_close.focus_next = modal_close.get_path()
	modal_close.focus_previous = modal_close.get_path()
	modal.hide()

func _queue_layout() -> void:
	if _layout_queued: return
	_layout_queued = true
	_adapt_layout.call_deferred()

func _adapt_layout() -> void:
	_layout_queued = false
	if not is_instance_valid(layout) or size.x < 1: return
	_compact = size.x < 760
	var factor := 1.0 if _compact else clampf(minf(size.x/1280.0,size.y/720.0),0.75,1.6)
	var width := (size.x-8.0 if _compact else size.x)/factor
	var height := size.y/factor
	layout.scale = Vector2.ONE*factor
	layout.size = Vector2(width,height)
	header.vertical = _compact
	header.add_theme_constant_override("separation",6 if _compact else 24)
	%Title.add_theme_font_size_override("font_size",30 if _compact else 46)
	%SituationTitle.add_theme_font_size_override("font_size",23 if _compact else 30)
	header.get_node("Divider").visible = not _compact
	%Landscape.visible = not _compact and width >= 1200
	body.vertical = _compact
	footer.vertical = _compact
	footer_actions.vertical = _compact and size.x < 430
	%Mentor.visible = not _compact
	sidebar.custom_minimum_size.x = 0 if _compact else 280
	steps_box.vertical = not _compact
	step_track.custom_minimum_size.y = 56 if _compact else 340
	step_track.size_flags_vertical = Control.SIZE_FILL if _compact else Control.SIZE_EXPAND_FILL
	illustration.custom_minimum_size.y = width*0.92 if _compact else 0
	detail.custom_minimum_size.y = detail_copy.get_combined_minimum_size().y+badges.get_combined_minimum_size().y+58 if _compact else 0
	detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if _compact else ScrollContainer.SCROLL_MODE_AUTO
	%Previous.size_flags_horizontal = Control.SIZE_FILL
	%Next.size_flags_horizontal = Control.SIZE_FILL
	for i in steps.size():
		steps[i].compact = _compact
		steps[i].text = str(i+1) if _compact else ["Обращение","Ваше\nрешение","Реакция","Результат"][i]
		steps[i].tooltip_text = ["Обращение","Ваше решение","Реакция","Результат"][i] if _compact else ""
		steps[i].queue_redraw()
	badges.vertical = _compact and size.x < 430
	canvas.custom_minimum_size.y = maxf(size.y,layout.get_combined_minimum_size().y*factor)
	layout.size.y = maxf(height,layout.get_combined_minimum_size().y)
	_update_track.call_deferred()

func _update_track() -> void:
	if steps.is_empty() or steps[selected_step].size.x < 1: return
	if _step_motion and _step_motion.is_valid(): _step_motion.kill()
	var b: Control = steps[selected_step]
	highlight.position = b.position
	highlight.polygon = PackedVector2Array([Vector2.ZERO,Vector2(b.size.x-16,0),Vector2(b.size.x,b.size.y*0.5),Vector2(b.size.x-16,b.size.y),Vector2(0,b.size.y)])
	rail.visible = not _compact
	if not _compact:
		rail.points = PackedVector2Array([Vector2(23,steps[0].size.y*0.5),Vector2(23,steps[3].position.y+steps[3].size.y*0.5)])

func _visibility() -> void:
	if not is_node_ready(): return
	if not is_visible_in_tree():
		modal.hide()
		return
	var config := ConfigFile.new()
	if config.load("user://menu-settings.cfg") == OK:
		reduced_motion = bool(config.get_value("accessibility","reduced_motion",false))
	for b in find_children("*","Button",true,false):
		if b.get_script() == ReviewButton: b.reduced_motion = reduced_motion
	_open.call_deferred()

func _open() -> void:
	if _entry_motion and _entry_motion.is_valid(): _entry_motion.kill()
	if _page_motion and _page_motion.is_valid(): _page_motion.kill()
	detail_copy.modulate.a = 1
	old_picture.hide()
	_adapt_layout()
	if reduced_motion:
		for node in [header,sidebar,illustration,detail,footer]: node.modulate.a = 1
		return
	_entry_motion = create_tween().set_ignore_time_scale(true).set_parallel(true)
	var nodes := [header,sidebar,illustration,detail,footer]
	for i in nodes.size():
		nodes[i].modulate.a = 0
		_entry_motion.tween_property(nodes[i],"modulate:a",1.0,0.36).set_delay(i*0.055).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# No timer advances the lesson: every section stays on screen until the player acts.

func present_effect(entry: Dictionary, state: Dictionary) -> void:
	final_report = false
	saved_report = {}
	context = state
	history = [entry]
	page = 0
	%Back.text = "К ВАГОНУ"
	%Continue.text = "ПРОДОЛЖИТЬ ДИАЛОГ"
	_set_history()

func present_report(report: Dictionary, trip: Dictionary = {}) -> void:
	final_report = true
	saved_report = report
	context = report if not report.get("incidents",[]).is_empty() else trip
	history = report.get("history",[])
	page = 0
	%Back.text = "К ОТЧЁТУ"
	%Continue.text = "К НОВОЙ ТРЕНИРОВКЕ"
	_set_history()

func _set_history() -> void:
	if _scroll_motion and _scroll_motion.is_valid(): _scroll_motion.kill()
	selected_step = 1
	selector.clear()
	var seen: Array[String] = []
	for i in history.size():
		var id := str(history[i].get("incident_id",""))
		if id in seen: continue
		seen.append(id)
		selector.add_item(_title(history[i]),i)
	selector.visible = seen.size() > 1
	_render_page()
	scroll_vertical = 0
	detail_scroll.scroll_vertical = 0
	detail_scroll.set_deferred("scroll_vertical",0)

func _incident(entry: Dictionary) -> Dictionary:
	for incident in context.get("incidents",[]):
		if incident.get("id") == entry.get("incident_id"): return incident
	return {}

func _kind(entry: Dictionary) -> String:
	var incident := _incident(entry)
	var source := str(incident.get("marker_id",entry.get("incident_id",entry.get("scenario_id",""))))
	for key in TITLES:
		if source.contains(key): return key
	return ""

func _title(entry: Dictionary) -> String:
	var incident := _incident(entry)
	return str(incident.get("title",TITLES.get(_kind(entry),incident.get("text","Решение по обращению"))))

func _render_page() -> void:
	if not is_node_ready(): return
	page = clampi(page,0,maxi(0,history.size()-1))
	%PageLabel.text = "%s / %s" % [page+1 if not history.is_empty() else 0,history.size()]
	%Previous.disabled = page == 0
	%Next.disabled = page >= history.size()-1
	%Previous.refresh()
	%Next.refresh()
	%ServiceChoice.hide()
	%Choice.show()
	if history.is_empty():
		%SituationTitle.text = "Пока нет решений"
		%Situation.text = "В этом рейсе ещё нет сохранённых действий."
		%Choice.text = "Вернитесь к отчёту или начните новую тренировку."
		%Effect.text = "Последствия появятся после первого решения."
		%Explanation.text = "Каждое действие можно будет разобрать отдельно."
		%Recommendation.text = "Начните с обращения пассажира и внимательно проверьте условия."
		picture.texture = null
		picture_open.disabled = true
		badges.hide()
		section_headers[3].text = "РАЗБОР"
	else:
		var entry: Dictionary = history[page]
		var incident := _incident(entry)
		var kind := _kind(entry)
		%SituationTitle.text = _title(entry)
		%Situation.text = str(entry.get("situation_text",SITUATIONS.get(kind,incident.get("text","Обращение пассажира."))))
		%Choice.text = str(entry.get("selected_text","Действие не указано."))
		if entry.get("source") == "service" and entry.get("node_after") == "completed":
			%Choice.hide()
			%ServiceChoice.show()
			%ServiceChoice.text = {"blanket":"Принесли пассажиру плед.","table":"Убрали использованную посуду со столика."}.get(kind,"Выполнили просьбу пассажира.")
			%ServiceChoice.tooltip_text = %Choice.text
		var effects: Dictionary = entry.get("effects",{})
		var facts: Dictionary = effects.get("facts",{})
		var outcome := Text.facts(facts)
		if entry.get("source") == "service" and entry.get("node_after") == "completed":
			outcome = "Просьба пассажира выполнена."
		if outcome.is_empty():
			outcome = _fact_summary(facts)
		%Effect.text = outcome if not outcome.is_empty() else str(entry.get("explanation","Для этого действия отдельный результат не указан."))
		%Explanation.text = str(entry.get("explanation","Объяснение для этого действия не сохранено."))
		var lesson := Progress.lesson(entry,context)
		%Choice.text = lesson.choice
		%Effect.text = lesson.outcome
		%Explanation.text = lesson.explanation
		# Neutral wording avoids calling a wrong choice successful.
		var met := false
		var missed := false
		for evidence in entry.get("competency_evidence",[]):
			met = met or evidence.get("result") == "met"
			missed = missed or evidence.get("result") in ["not_met","missed","failed"]
		var delta := _loyalty_delta(effects)
		var has_delta: bool = effects.has("loyalty_delta") or not effects.get("loyalty_deltas",{}).is_empty()
		section_headers[3].text = "ПОЧЕМУ ЭТО СРАБОТАЛО" if (met or (has_delta and delta > 0)) and delta >= 0 and float(effects.get("safety_delta",0)) >= 0 and not missed and effects.get("critical_marks",[]).is_empty() else "РАЗБОР РЕШЕНИЯ"
		%Loyalty.text = ("Лояльность "+("+" if delta > 0 else "")+Text.metric(delta)) if has_delta else "Лояльность —"
		loyalty_badge.palette = "sage" if delta >= 0 else "gold"
		loyalty_badge.queue_redraw()
		%Loyalty.tooltip_text = Text.effects(effects)
		var marks: Array = effects.get("critical_marks",[])
		if not marks.is_empty():
			%Result.text = "!  Есть риск"
		elif facts.get("aisle_clear",false):
			%Result.text = "✓  Проход свободен"
		elif facts.get("agreement_verified",false) or facts.get("seat_verified",false):
			%Result.text = "✓  Итог проверен"
		elif effects.has("safety_delta"):
			%Result.text = "Безопасность "+("+" if effects.safety_delta > 0 else "")+Text.metric(effects.safety_delta)
		elif entry.get("source") == "service" and entry.get("node_after") == "completed":
			%Result.text = "✓  Выполнено"
		else:
			%Result.text = "Действие сохранено"
		result_badge.palette = "gold" if not marks.is_empty() else "sage"
		result_badge.queue_redraw()
		%Result.tooltip_text = Text.effects(effects)
		badges.show()
		%Recommendation.text = str(incident.get("recommendation",saved_report.get("recommendation","Проверяйте условия до обещания и уточняйте, помогло ли ваше решение.")))
		%Evidence.text = "Запись: %s\n%s → %s\nНа решение: %s с" % [entry.get("request_id","—"),entry.get("node_before","—"),entry.get("node_after","—"),Text.metric(entry.get("decision_time_seconds"))]
		%PageLabel.tooltip_text = "Время рейса: "+Progress.elapsed(entry.get("simulation_time"))
		%Summary.text = str(saved_report.get("summary",""))
		%Facts.text = Text.facts(context.get("facts",{}))+"\n"+Text.scales(context.get("scales",{}))
		%Persistence.text = "Сохранённый разбор"
		%TripId.text = str(saved_report.get("trip_id",""))
		picture.texture = ART.get(kind)
		picture_open.disabled = picture.texture == null
		for i in selector.item_count:
			if history[selector.get_item_id(i)].get("incident_id") == entry.get("incident_id"):
				selector.select(i)
				break
	for i in 4:
		steps[i].selected = i == selected_step
		steps[i].refresh()
		section_headers[i].emphasis = 1.0 if i == selected_step else 0.0
	_queue_layout()

func _fact_summary(facts: Dictionary) -> String:
	var labels := {"interests_checked":"Интересы обеих сторон уточнены.","agreement_verified":"Договорённость проверена.","seat_verified":"Места пассажиров проверены.","tickets_checked":"Билеты проверены.","moved":"Пассажиру помогли пересесть."}
	var parts: Array[String] = []
	for key in labels:
		if facts.get(key,false) is bool and facts.get(key,false): parts.append(labels[key])
	return " ".join(parts)

func _loyalty_delta(effects: Dictionary) -> float:
	var deltas: Dictionary = effects.get("loyalty_deltas",{})
	if deltas.is_empty(): return float(effects.get("loyalty_delta",0))
	var total := 0.0
	for delta in deltas.values(): total += float(delta)
	return total

func select_evidence(request_id: String) -> void:
	if request_id.is_empty(): return
	if _scroll_motion and _scroll_motion.is_valid(): _scroll_motion.kill()
	detail_scroll.scroll_vertical = 0
	detail_scroll.set_deferred("scroll_vertical",0)
	for i in history.size():
		if history[i].get("request_id") == request_id:
			page = i
			_render_page()
			return
	%Evidence.text = "Связанное действие не найдено в этом отчёте."
	%PageLabel.tooltip_text = %Evidence.text

func _turn_page(target: int) -> void:
	target = clampi(target,0,maxi(0,history.size()-1))
	if target == page: return
	if _page_motion and _page_motion.is_valid(): _page_motion.kill()
	if _scroll_motion and _scroll_motion.is_valid(): _scroll_motion.kill()
	if _entry_motion and _entry_motion.is_valid(): _entry_motion.kill()
	for node in [header,sidebar,illustration,detail,footer]: node.modulate.a = 1
	old_picture.texture = picture.texture
	old_picture.modulate.a = 1
	old_picture.visible = old_picture.texture != null
	page = target
	_render_page()
	detail_scroll.scroll_vertical = 0
	detail_scroll.set_deferred("scroll_vertical",0)
	if _compact: scroll_vertical = 0
	if reduced_motion:
		detail_copy.modulate.a = 1
		old_picture.hide()
		return
	detail_copy.modulate.a = 0.15
	_page_motion = create_tween().set_ignore_time_scale(true).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_page_motion.tween_property(detail_copy,"modulate:a",1.0,0.26)
	_page_motion.tween_property(old_picture,"modulate:a",0.0,0.32)
	_page_motion.chain().tween_callback(old_picture.hide)

func _choose_incident(index: int) -> void:
	_turn_page(selector.get_item_id(index))

func _select_step(index: int) -> void:
	if _step_motion and _step_motion.is_valid(): _step_motion.kill()
	if _scroll_motion and _scroll_motion.is_valid(): _scroll_motion.kill()
	selected_step = index
	for i in 4:
		steps[i].selected = i == index
		steps[i].refresh()
	if reduced_motion:
		highlight.position = steps[index].position
		for i in 4: section_headers[i].emphasis = 1.0 if i == index else 0.0
	else:
		_step_motion = create_tween().set_ignore_time_scale(true).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_step_motion.tween_property(highlight,"position",steps[index].position,0.28)
		for i in 4: _step_motion.tween_property(section_headers[i],"emphasis",1.0 if i == index else 0.0,0.24)
	var target: float = sections[index].position.y
	var scroll: ScrollContainer = scroller if _compact else detail_scroll
	if _compact: target = detail.position.y+22+sections[index].position.y
	var bar := scroll.get_v_scroll_bar()
	target = clampf(target,0,maxf(0,bar.max_value-bar.page))
	if reduced_motion:
		scroll.scroll_vertical = roundi(target)
	else:
		_scroll_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_scroll_motion.tween_property(scroll,"scroll_vertical",roundi(target),0.28)

func _art_hover(active: bool) -> void:
	if _art_motion and _art_motion.is_valid(): _art_motion.kill()
	picture.pivot_offset = picture.size*0.5
	if reduced_motion:
		picture.scale = Vector2.ONE
		return
	_art_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_art_motion.tween_property(picture,"scale",Vector2.ONE*(1.018 if active else 1.0),0.38)

func _open_art() -> void:
	if picture.texture == null: return
	if _modal_motion and _modal_motion.is_valid(): _modal_motion.kill()
	previous_focus = get_viewport().gui_get_focus_owner()
	modal_picture.texture = picture.texture
	modal.show()
	modal_close.grab_focus()
	modal.modulate.a = 1 if reduced_motion else 0
	if not reduced_motion:
		_modal_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_modal_motion.tween_property(modal,"modulate:a",1.0,0.24)

func _close_art() -> void:
	if _modal_motion and _modal_motion.is_valid(): _modal_motion.kill()
	if reduced_motion:
		_finish_art_close()
	else:
		_modal_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_modal_motion.tween_property(modal,"modulate:a",0.0,0.18)
		_modal_motion.tween_callback(_finish_art_close)

func _finish_art_close() -> void:
	modal.hide()
	if is_instance_valid(previous_focus): previous_focus.grab_focus()
	else: picture_open.grab_focus()

func set_locked(locked: bool) -> void:
	_locked = locked
	if is_node_ready():
		%Continue.disabled = locked
		%Continue.refresh()

func _on_previous() -> void: _turn_page(page-1)
func _on_next() -> void: _turn_page(page+1)
func _on_back() -> void:
	if final_report: report_requested.emit()
	else: back_requested.emit()
func _on_continue() -> void:
	if not _locked: continue_requested.emit()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	if modal.visible:
		if event.keycode == KEY_ESCAPE: _close_art()
		if event.keycode != KEY_TAB and event.keycode != KEY_ENTER and event.keycode != KEY_SPACE:
			get_viewport().set_input_as_handled()
		return
	# The native popup owns its arrows and Escape while choosing a situation.
	if selector.get_popup().visible: return
	match event.keycode:
		KEY_ESCAPE: _on_back()
		KEY_LEFT: _on_previous()
		KEY_RIGHT: _on_next()
		KEY_1,KEY_2,KEY_3,KEY_4: _select_step(event.keycode-KEY_1)
		KEY_TAB,KEY_UP,KEY_DOWN:
			if get_viewport().gui_get_focus_owner() == null:
				steps[selected_step].grab_focus()
			else: return
		_: return
	get_viewport().set_input_as_handled()
