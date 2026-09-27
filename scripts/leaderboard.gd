extends Control
signal list_requested(scope: String, page: int)
signal replay_requested
signal profile_requested
signal notifications_requested
const Paper = preload("res://scripts/report/panel.gd")
const Action = preload("res://scripts/debrief/review_button.gd")
const Nav = preload("res://scripts/profile/nav_button.gd")
const ScopeButton = preload("res://scripts/leaderboard/scope_button.gd")
const Entry = preload("res://scripts/leaderboard/entry.gd")
const Text = preload("res://scripts/server_text.gd")
const SCOPES := {"crew":"Бригада", "depot":"Депо", "company":"Компания"}
var scope := "crew"
var requested_page := 1
var page_size := 3
var total := 0
var reduced_motion := false
var busy := false
var entries: Array = []
var rows: Array[Button] = []
var buttons: Array[Button] = []
var scroller: ScrollContainer
var canvas: Control
var stage: Control
var board: Control
var list_box: VBoxContainer
var list_scroll: ScrollContainer
var modal: Control
var modal_panel: PanelContainer
var previous_focus: Control
var entrance: Tween
var reveal: Tween
var scope_motion: Tween
var modal_motion: Tween
var compact := false
var scroll_vertical: int:
	get: return scroller.scroll_vertical if is_instance_valid(scroller) else 0
	set(value):
		if is_instance_valid(scroller): scroller.scroll_vertical = value

func _named(n: Node, id: String, p: Node) -> void:
	n.name = id
	p.add_child(n)
	n.owner = self
	n.unique_name_in_owner = true
func _rect(n: Control, r: Rect2) -> void:
	n.position = r.position
	n.size = r.size
func _label(id: String, text: String, p: Node, fs := 27, heading := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size",fs)
	if heading: l.add_theme_font_override("font",get_theme_font("font","Heading"))
	_named(l,id,p)
	return l
func _panel(id: String, p: Node, palette := "paper") -> Control:
	var panel := Paper.new()
	panel.palette = palette
	panel.cut = 27
	panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	_named(panel,id,p)
	var c := Control.new()
	c.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(c)
	return c
func _button(id: String, text: String, p: Node, cb: Callable, type := "action") -> Button:
	var b: Button = Nav.new() if type == "nav" else (ScopeButton.new() if type == "scope" else Action.new())
	b.text = text
	b.clip_text = true
	b.custom_minimum_size = Vector2(44,52)
	_named(b,id,p)
	b.pressed.connect(cb)
	buttons.append(b)
	return b
func _color(id: String, p: Node, color: Color) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.mouse_filter = MOUSE_FILTER_IGNORE
	_named(c,id,p)
	return c
func _ready() -> void:
	clip_contents = true
	var bg := TextureRect.new()
	bg.texture = preload("res://assets/leaderboard/carriage.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := _color("Shade",self,Color(0.1,0.16,0.18,0.10))
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroller = ScrollContainer.new()
	add_child(scroller)
	scroller.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.follow_focus = true
	canvas = Control.new()
	canvas.size_flags_horizontal = SIZE_EXPAND_FILL
	scroller.add_child(canvas)
	stage = Control.new()
	canvas.add_child(stage)
	var header := _panel("RatingHeader",stage,"dark")
	_label("Brand","НАЧАЛЬНИК РЕЙСА",header,37,true).add_theme_color_override("font_color",Color("eee8da"))
	for s in [["Trips","РЕЙСЫ",func(): replay_requested.emit()],["Profile","ПРОФИЛЬ",func(): profile_requested.emit()],["Rating","РЕЙТИНГ",func(): _close_detail()],["Notices","УВЕДОМЛЕНИЯ",func(): notifications_requested.emit()]]:
		var b := _button(s[0],s[1],header,s[2],"nav")
		b.kind = "primary" if s[0] == "Rating" else "secondary"
	board = _panel("Board",stage)
	_label("Title","РЕЙТИНГ",board,76,true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_color("FilterTrack",board,Color("cfcdc1"))
	_color("ScopeHighlight",board,Color("d3af64"))
	for id in SCOPES:
		_button(id,str(SCOPES[id]).to_upper(),board,_on_scope.bind(id),"scope").selected = id == scope
	_label("Subtitle","Одинаковые сценарии · Учебный режим",board,26).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_color("TableHead",board,Color("c4c3b7"))
	_label("PlaceColumn","МЕСТО",board,23,true)
	_label("NameColumn","УЧАСТНИК",board,23,true)
	_label("ScoreColumn","ОЧКИ",board,23,true).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	list_scroll = ScrollContainer.new()
	_named(list_scroll,"ListScroll",board)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation",0)
	list_scroll.add_child(list_box)
	_label("Empty","Здесь появятся результаты завершённых рейсов.",board,30).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("PageLabel","",board,22).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button("Previous","НАЗАД",board,_move.bind(-1))
	_button("Next","ДАЛЕЕ",board,_move.bind(1))
	var stamp := _label("DemoNotice","ДЕМОНСТРАЦИОННЫЕ ДАННЫЕ",board,25,true)
	stamp.add_theme_color_override("font_color",Color("a85444"))
	var stamp_border := StyleBoxFlat.new()
	stamp_border.bg_color = Color.TRANSPARENT
	stamp_border.border_color = Color("ac6150")
	stamp_border.set_border_width_all(3)
	stamp_border.set_content_margin_all(8)
	stamp.add_theme_stylebox_override("normal",stamp_border)
	stamp.rotation = -0.025
	_label("RowHint","Выберите участника, чтобы рассмотреть результат",board,21).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var own := _panel("OwnCard",stage)
	var trophy := preload("res://scripts/leaderboard/emblem.gd").new()
	_named(trophy,"Trophy",own)
	_color("OwnRule",own,Color("989482"))
	_label("OwnTitle","ВАШЕ МЕСТО",own,28,true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_named(preload("res://scripts/leaderboard/laurel.gd").new(),"Laurel",own)
	_label("OwnRank","—",own,90,true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("OwnHint","Завершите учебный рейс",own,22).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := _panel("NoteCard",stage)
	_label("Note","Учитывается лучший\nрезультат сценария.\nПовтор добавляет\nтолько улучшение.",note,26)
	_color("NoteRule",note,Color("989482"))
	var footer := _panel("RatingFooter",stage,"dark")
	_label("Status","",footer,22).add_theme_color_override("font_color",Color("e1e0d4"))
	_button("Refresh","ОБНОВИТЬ",footer,_on_refresh)
	_make_modal()
	resized.connect(_adapt_layout)
	visibility_changed.connect(_visibility)
	_adapt_layout()
	_update_pager()
	%DemoNotice.hide()
	%RowHint.hide()

func _make_modal() -> void:
	modal = Control.new()
	add_child(modal)
	modal.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color(0.07,0.11,0.14,0.72)
	modal.add_child(veil)
	veil.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	veil.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _close_detail())
	var content := _panel("DetailPanel",modal)
	modal_panel = content.get_parent()
	_label("DetailEyebrow","РЕЗУЛЬТАТ УЧАСТНИКА",content,24,true).add_theme_color_override("font_color",Color("766440"))
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_named(detail_scroll,"DetailScroll",content)
	var detail_box := VBoxContainer.new()
	detail_box.size_flags_horizontal = SIZE_EXPAND_FILL
	detail_box.add_theme_constant_override("separation",20)
	detail_scroll.add_child(detail_box)
	_label("DetailName","",detail_box,38,true)
	_label("DetailScore","",detail_box,45,true)
	_label("DetailCopy","",detail_box,26)
	_button("CloseDetail","ЗАКРЫТЬ",content,_close_detail).kind = "primary"
	modal.hide()

func _adapt_layout() -> void:
	if not is_instance_valid(stage): return
	compact = size.x < 900
	var w := 560.0 if compact else 1672.0
	var h := 1500.0 if compact else 941.0
	var factor := maxf(0.1,(size.x-(12 if compact else 0))/w)
	if not compact: factor = minf(factor,size.y/h)
	stage.scale = Vector2.ONE*factor
	stage.size = Vector2(w,h)
	stage.position = Vector2(maxf(0,(size.x-w*factor)/2),maxf(0,(size.y-h*factor)/2))
	canvas.custom_minimum_size.y = h*factor
	_rect(%RatingHeader,Rect2(0,0,w,150 if compact else 70))
	_rect(%Brand,Rect2(24 if compact else 58,8,510,54))
	var nav_x := 12.0 if compact else 690.0
	var nav_w := 134.0 if compact else 232.0
	for i in 4:
		_rect(get_node("%"+["Trips","Profile","Rating","Notices"][i]),Rect2(nav_x+i*nav_w,76 if compact else 0,nav_w,66 if compact else 70))
	_rect(%Board,Rect2(12,366,536,820) if compact else Rect2(400,90,862,798))
	var bw := 536.0 if compact else 862.0
	var inset := 20.0 if compact else 60.0
	var tw := bw-inset*2
	_rect(%Title,Rect2(inset,12,tw,102))
	_rect(%FilterTrack,Rect2(inset,122,tw,62))
	for i in 3:
		var b: Button = get_node("%"+str(SCOPES.keys()[i]))
		_rect(b,Rect2(inset+i*tw/3,122,tw/3,62))
	%ScopeHighlight.size = Vector2(tw/3,62)
	if not scope_motion or not scope_motion.is_running():
		%ScopeHighlight.position = Vector2(inset+SCOPES.keys().find(scope)*tw/3,122)
	_rect(%Subtitle,Rect2(inset,196,tw,50))
	_rect(%TableHead,Rect2(inset,250,tw,43))
	_rect(%PlaceColumn,Rect2(inset+12,253,95,36))
	_rect(%NameColumn,Rect2(inset+(192 if compact else 250),253,230,36))
	_rect(%ScoreColumn,Rect2(bw-inset-110,253,86,36))
	_rect(list_scroll,Rect2(inset,293,tw,440))
	_rect(%Empty,Rect2(inset+24,365,tw-48,170))
	_rect(%Previous,Rect2(inset,749 if compact else 728,125,54))
	_rect(%Next,Rect2(bw-inset-125,749 if compact else 728,125,54))
	_rect(%PageLabel,Rect2(inset+130,752 if compact else 731,tw-260,45))
	_rect(%DemoNotice,Rect2(bw-inset-390,742 if rows.size() >= 5 else 677,390,44))
	%DemoNotice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(%RowHint,Rect2(inset,679,tw,44))
	# Three records is the server's negotiated page size; five-row previews also fit.
	for row in rows:
		row.compact_row = compact
		row.custom_minimum_size.y = 88 if rows.size() >= 5 else 118
		row.queue_redraw()
	_rect(%OwnCard,Rect2(12,168,536,180) if compact else Rect2(120,315,252,470))
	_rect(%Trophy,Rect2(30,26,108,113) if compact else Rect2(37,53,178,186))
	_rect(%OwnRule,Rect2(160,26,2,124) if compact else Rect2(35,264,182,2))
	_rect(%OwnTitle,Rect2(181,17,330,45) if compact else Rect2(12,283,228,45))
	_rect(%OwnRank,Rect2(179,52,148,101) if compact else Rect2(22,326,208,106))
	_rect(%Laurel,Rect2(20,325,212,109))
	%Laurel.visible = not compact
	_rect(%OwnHint,Rect2(340,63,160,90) if compact else Rect2(18,427,216,36))
	_rect(%NoteCard,Rect2(12,1204,536,162) if compact else Rect2(1318,376,310,215))
	_rect(%Note,Rect2(28,24,480,122) if compact else Rect2(34,28,252,151))
	_rect(%NoteRule,Rect2(40,178,80,2))
	%NoteRule.visible = not compact
	_rect(%RatingFooter,Rect2(0,1386,w,114) if compact else Rect2(0,902,w,39))
	_rect(%Status,Rect2(26,8,w-220,98) if compact else Rect2(58,3,1280,33))
	_rect(%Refresh,Rect2(w-182,30,160,57) if compact else Rect2(w-222, -15,182,52))
	%Refresh.add_theme_font_size_override("font_size",21)
	var mf := minf(1.0,minf((size.x-28)/600,(size.y-28)/480))
	modal_panel.size = Vector2(600,480)
	modal_panel.scale = Vector2.ONE*mf
	modal_panel.position = (size-Vector2(600,480)*mf)/2
	_rect(%DetailEyebrow,Rect2(38,32,524,42))
	_rect(%DetailScroll,Rect2(38,84,524,296))
	_rect(%CloseDetail,Rect2(38,399,524,55))

func _visibility() -> void:
	if not is_visible_in_tree():
		_close_detail(true)
		return
	for b in buttons: b.reduced_motion = reduced_motion
	for row in rows: row.reduced_motion = reduced_motion
	if entrance and entrance.is_valid(): entrance.kill()
	for n in [%Board,%OwnCard,%NoteCard]: n.modulate.a = 1.0
	if not reduced_motion:
		entrance = create_tween().set_parallel(true).set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		for i in 3:
			var n: Control = [%Board,%OwnCard,%NoteCard][i]
			n.modulate.a = 0.0
			entrance.tween_property(n,"modulate:a",1.0,0.42).set_delay(i*0.08)
	get_node("%"+scope).grab_focus()

func loading() -> void:
	busy = true
	_close_detail(true)
	if reveal and reveal.is_valid(): reveal.kill()
	list_box.modulate.a = 1
	for row in rows: row.hide()
	%Empty.text = "Загружаем рейтинг…"
	%Empty.show()
	%OwnRank.text = "—"
	%OwnHint.text = "Загружаем место"
	%DemoNotice.hide()
	%RowHint.hide()
	%Status.text = "Загружаем: "+str(SCOPES[scope]).to_lower()
	%Refresh.disabled = true
	_update_pager()
func failed(message: String) -> void:
	busy = false
	for row in rows: row.hide()
	%Empty.text = "Рейтинг не загружен.\nНажмите «Повторить»."
	%Empty.show()
	%OwnRank.text = "—"
	%OwnHint.text = "Место не подтверждено"
	%Status.text = message
	%Refresh.text = "ПОВТОРИТЬ"
	%Refresh.disabled = false
	%Previous.disabled = true
	%Next.disabled = true
func present(value: Dictionary) -> void:
	busy = false
	_close_detail(true)
	if reveal and reveal.is_valid(): reveal.kill()
	for row in rows:
		list_box.remove_child(row)
		row.queue_free()
	rows.clear()
	entries = value.get("entries",[])
	requested_page = int(value.get("page",1))
	page_size = int(value.get("page_size",3))
	total = int(value.get("total",entries.size()))
	%OwnRank.text = "—"
	%OwnHint.text = "Не на этой странице" if total > entries.size() else "Пока нет результата"
	var demo := false
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var row := Entry.new()
		row.entry = entry
		var known_face := ["Ирина","Сергей","Алексей","Мария","Олег"].find(str(entry.display_name))
		row.face = known_face if known_face >= 0 else (2 if entry.get("is_self",false) else absi(str(entry.display_name).hash()) % 5)
		row.reduced_motion = reduced_motion
		row.size_flags_horizontal = SIZE_EXPAND_FILL
		row.tooltip_text = "%s · место %s · %s очков" % [entry.display_name,int(entry.rank),Text.metric(entry.total_points)]
		row.accessibility_name = row.tooltip_text
		row.pressed.connect(_open_detail.bind(i))
		list_box.add_child(row)
		rows.append(row)
		if entry.get("is_self",false):
			%OwnRank.text = str(int(entry.rank))
			%OwnHint.text = str(SCOPES[scope])
		demo = demo or entry.get("is_demo",false)
	%DemoNotice.visible = demo
	%RowHint.visible = not demo and not entries.is_empty()
	%Empty.visible = entries.is_empty()
	%Empty.text = "Пока нет результатов.\nЗавершите учебный рейс — и ваше место появится здесь."
	%Status.text = "Лучшие результаты · "+str(SCOPES[scope])
	%Refresh.disabled = false
	%Refresh.text = "ОБНОВИТЬ"
	list_scroll.scroll_vertical = 0
	_adapt_layout()
	_update_pager()
	if not reduced_motion and is_visible_in_tree() and not rows.is_empty():
		reveal = create_tween().set_parallel(true).set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		for i in rows.size():
			rows[i].modulate.a = 0.0
			reveal.tween_property(rows[i],"modulate:a",1.0,0.28).set_delay(i*0.065)
func _update_pager() -> void:
	var pages := maxi(1,ceili(float(total)/maxi(1,page_size)))
	%PageLabel.text = "%s / %s" % [requested_page,pages]
	%Previous.disabled = busy or requested_page <= 1
	%Next.disabled = busy or requested_page >= pages
	%Previous.visible = pages > 1
	%Next.visible = pages > 1
	%PageLabel.visible = pages > 1
func _on_scope(value: String) -> void:
	if value == scope: return
	scope = value
	requested_page = 1
	if scope_motion and scope_motion.is_valid(): scope_motion.kill()
	for id in SCOPES:
		var b: Button = get_node("%"+id)
		b.selected = id == scope
		b.queue_redraw()
	var target: float = get_node("%"+scope).position.x
	if reduced_motion: %ScopeHighlight.position.x = target
	else:
		scope_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		scope_motion.tween_property(%ScopeHighlight,"position:x",target,0.26)
	loading()
	list_requested.emit(scope,requested_page)
func _move(direction: int) -> void:
	if busy: return
	var page := clampi(requested_page+direction,1,maxi(1,ceili(float(total)/maxi(1,page_size))))
	if page == requested_page: return
	requested_page = page
	loading()
	list_requested.emit(scope,page)
func _on_refresh() -> void:
	if busy: return
	loading()
	list_requested.emit(scope,requested_page)
func _open_detail(index: int) -> void:
	if busy or index >= entries.size(): return
	var entry: Dictionary = entries[index]
	previous_focus = rows[index]
	%DetailName.text = str(entry.display_name)+(" · Вы" if entry.get("is_self",false) else "")
	%DetailScore.text = "%s место     %s очков" % [int(entry.rank),Text.metric(entry.total_points)]
	%DetailScroll.scroll_vertical = 0
	%DetailCopy.text = str(SCOPES[scope])+"\n"+("Демонстрационная запись. Участник вымышленный." if entry.get("is_demo",false) else "Сумма лучших результатов завершённых сценариев.")
	for b in buttons: b.focus_mode = FOCUS_NONE
	for row in rows: row.focus_mode = FOCUS_NONE
	%CloseDetail.focus_mode = FOCUS_ALL
	modal.show()
	if modal_motion and modal_motion.is_valid(): modal_motion.kill()
	modal.modulate.a = 1.0 if reduced_motion else 0.0
	if not reduced_motion:
		modal_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		modal_motion.tween_property(modal,"modulate:a",1.0,0.22)
	%CloseDetail.grab_focus()
func _close_detail(immediate := false) -> void:
	if not is_instance_valid(modal) or not modal.visible: return
	if modal_motion and modal_motion.is_valid(): modal_motion.kill()
	if immediate or reduced_motion:
		_finish_close()
	else:
		modal_motion = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		modal_motion.tween_property(modal,"modulate:a",0.0,0.15)
		modal_motion.tween_callback(_finish_close)
func _finish_close() -> void:
	modal.hide()
	for b in buttons: b.focus_mode = FOCUS_ALL
	for row in rows: row.focus_mode = FOCUS_ALL
	if is_instance_valid(previous_focus) and previous_focus.is_visible_in_tree(): previous_focus.grab_focus()
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and modal.visible:
		_close_detail()
		get_viewport().set_input_as_handled()
