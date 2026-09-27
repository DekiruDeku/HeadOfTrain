extends Control
signal report_requested(trip_id: String)
signal refresh_requested
signal replay_requested
signal leaderboard_requested
signal notifications_requested
const Text = preload("res://scripts/server_text.gd")
const Paper = preload("res://scripts/report/panel.gd")
const ReviewButton = preload("res://scripts/debrief/review_button.gd")
const NavButton = preload("res://scripts/profile/nav_button.gd")
const Hit = preload("res://scripts/report/card_hit.gd")
const Portrait = preload("res://scripts/profile/portrait.gd")
const ART = preload("res://assets/profile/concept-atlas.png")
const SKILLS = [["communication","Коммуникация"],["conflict","Разрешение конфликтов"],["safety","Безопасность"],["service","Сервис"],["prioritization","Приоритизация"]]
const AWARDS = [["first_trip","Первый рейс","Первый рейс\nзавершён",Rect2(444,705,93,113)],["safety_resolved","Безопасный рейс","Без угроз\nбезопасности",Rect2(736,705,95,113)],["checked_before_promise","Проверил прежде,\nчем обещать","Условия\nпроверены",Rect2(1025,705,95,113)],["carriage-3","Новый вагон","Откроется позже",Rect2(1336,705,95,113)]]
var profile: Dictionary = {}
var reduced_motion := false
var scroller: ScrollContainer
var canvas: Control
var stage: Control
var body: Control
var groups: Array[Control] = []
var buttons: Array[Button] = []
var bars: Dictionary = {}
var targets: Dictionary = {}
var modal: Control
var modal_panel: PanelContainer
var modal_scroll: ScrollContainer
var record_copy: VBoxContainer
var records: Array = []
var record_page := 0
var section := "reports"
var previous_focus: Control
var entry_motion: Tween
var modal_motion: Tween
var page_motion: Tween
var _opening := false
var _compact := false
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
	n.set_deferred("size",r.size)
func _label(id: String, text: String, p: Node, fs := 27, heading := false) -> Label:
	var l := Label.new()
	_named(l,id,p)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size",fs)
	if heading: l.add_theme_font_override("font",get_theme_font("font","Heading"))
	return l
func _button(id: String, text: String, p: Node, cb: Callable, kind := "secondary") -> Button:
	var b: Button = NavButton.new() if id in ["Trips","ProfileTab","Rating","Notices"] else ReviewButton.new()
	if b is NavButton:
		b.glyph = load("res://assets/menu/"+str({"Trips":"train","ProfileTab":"person","Rating":"rating","Notices":"bell"}[id])+".svg")
	b.kind = kind
	b.text = text
	b.custom_minimum_size = Vector2(44,52)
	_named(b,id,p)
	b.pressed.connect(cb)
	buttons.append(b)
	return b
func _panel(id: String, p: Node, palette := "paper", pad := 0) -> PanelContainer:
	var panel := Paper.new()
	panel.palette = palette
	_named(panel,id,p)
	var style := StyleBoxEmpty.new()
	style.set_content_margin_all(pad)
	panel.add_theme_stylebox_override("panel",style)
	return panel
func _group(id: String) -> Control:
	var panel := _panel(id,body)
	groups.append(panel)
	var c := Control.new()
	panel.add_child(c)
	return c
func _art(id: String, region: Rect2, p: Node) -> TextureRect:
	var texture := AtlasTexture.new()
	texture.atlas = ART
	texture.region = region
	texture.filter_clip = true
	var t := TextureRect.new()
	t.texture = texture
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = MOUSE_FILTER_IGNORE
	_named(t,id,p)
	return t
func _line(id: String, p: Node) -> ColorRect:
	var l := ColorRect.new()
	l.color = Color("8c8d80")
	l.mouse_filter = MOUSE_FILTER_IGNORE
	_named(l,id,p)
	return l
func _hit(id: String, p: Control, cb: Callable, hint: String) -> Button:
	var b := Hit.new()
	_named(b,id,p)
	b.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	b.tooltip_text = hint
	b.accessibility_name = hint
	b.pressed.connect(cb)
	buttons.append(b)
	return b
func _ready() -> void:
	clip_contents = true
	var bg := ColorRect.new()
	bg.color = Color("626c6b")
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var grain := ShaderMaterial.new()
	grain.shader = preload("res://assets/debrief/paper.gdshader")
	bg.material = grain
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
	var header := _panel("ProfileHeader",stage,"dark")
	header.cut = 0
	var header_copy := Control.new()
	header.add_child(header_copy)
	_label("Brand","НАЧАЛЬНИК РЕЙСА",header_copy,31,true).add_theme_color_override("font_color",Color("eee8da"))
	for spec in [["Trips","РЕЙСЫ",func(): replay_requested.emit()],["ProfileTab","ПРОФИЛЬ",func(): _close_modal()],["Rating","РЕЙТИНГ",func(): leaderboard_requested.emit()],["Notices","УВЕДОМЛЕНИЯ",func(): notifications_requested.emit()]]:
		_button(spec[0],spec[1],header_copy,spec[2],"primary" if spec[0] == "ProfileTab" else "secondary")
	body = Control.new()
	_named(body,"Body",stage)
	body.mouse_filter = MOUSE_FILTER_IGNORE
	var identity := _group("IdentityCard")
	var portrait := Portrait.new()
	_named(portrait,"Portrait",identity)
	_label("PlayerName","ВАШ ПРОФИЛЬ",identity,43,true)
	_label("Role","Начальник рейса",identity,26)
	_label("Points","— очков",identity,39,true).add_theme_color_override("font_color",Color("805c29"))
	_line("IdentityRule",identity)
	_label("TripsCount","Рейсов завершено: —",identity,27)
	var skills := _group("SkillsCard")
	_label("Title","ПРОФИЛЬ",skills,55,true)
	_label("Subtitle","Ваш учебный прогресс",skills,28).add_theme_color_override("font_color",Color("626761"))
	_line("SkillsRule",skills)
	for i in SKILLS.size():
		var id: String = SKILLS[i][0]
		var row := Control.new()
		_named(row,id+"Row",skills)
		_label(id+"Name",SKILLS[i][1],row,27)
		var bar := ProgressBar.new()
		_named(bar,id+"Bar",row)
		bar.show_percentage = false
		bar.mouse_filter = MOUSE_FILTER_IGNORE
		var track := StyleBoxFlat.new()
		track.bg_color = Color("bbbcb4")
		track.set_corner_radius_all(3)
		var fill := track.duplicate()
		fill.bg_color = Color("506c7b") if i%2 == 0 else Color("738368")
		bar.add_theme_stylebox_override("background",track)
		bar.add_theme_stylebox_override("fill",fill)
		bars[id] = bar
		_label(id+"Value","—",row,25)
		_label(id+"Empty","Пока нет оценки",row,22).add_theme_color_override("font_color",Color("72766c"))
		_hit(id+"Details",row,_skill_details.bind(id),"Подробнее: "+SKILLS[i][1])
	_line("SkillsFootRule",skills)
	_label("SkillsNote","Очки по лучшим результатам рейсов",skills,23).add_theme_color_override("font_color",Color("626761"))
	var rec := _group("RecommendationCard")
	_label("RecTitle","РЕКОМЕНДУЕМ",rec,41,true)
	_line("RecRule",rec)
	_art("RecommendationArt",Rect2(1267,278,330,228),rec)
	_label("Recommendation","Проверка свободных мест",rec,29,true)
	_label("RecHint","Уточните условия, прежде чем обещать",rec,22)
	_button("Train","ТРЕНИРОВАТЬСЯ  ›",rec,func(): replay_requested.emit(),"primary").add_theme_font_size_override("font_size",29)
	for i in AWARDS.size():
		var award := _group("Award"+str(i))
		_art("AwardIcon"+str(i),AWARDS[i][3],award)
		_label("AwardTitle"+str(i),AWARDS[i][1],award,24,true)
		_label("AwardText"+str(i),"Пока не получено",award,22)
		_hit("AwardHit"+str(i),award,_award_details.bind(i),"Условия достижения: "+AWARDS[i][1].replace("\n"," "))
	var foot := _panel("Footer",stage,"dark")
	foot.cut = 0
	var fc := Control.new()
	foot.add_child(fc)
	_label("FooterHint","Каждый рейс — новый опыт",fc,25).add_theme_color_override("font_color",Color("dddcca"))
	_button("Archive","СОХРАНЁННЫЕ РАЗБОРЫ  ›",fc,_show_archive).add_theme_font_size_override("font_size",24)
	_button("Refresh","ОБНОВИТЬ",fc,func(): refresh_requested.emit())
	_label("Status","",stage,25).add_theme_color_override("font_color",Color("faf1df"))
	_build_modal()
	resized.connect(_adapt_layout)
	visibility_changed.connect(_visibility)
	_adapt_layout()
	body.hide()
func _adapt_layout() -> void:
	if not is_instance_valid(stage): return
	_compact = size.x < 900
	var width := 560.0 if _compact else 1672.0
	var height := 2334.0 if _compact else 941.0
	var factor := maxf(0.1,(size.x- (12 if _compact else 0))/width)
	if not _compact: factor = minf(factor,size.y/height)
	stage.scale = Vector2.ONE*factor
	stage.size = Vector2(width,height)
	stage.position = Vector2(maxf(0,(size.x-width*factor)/2),maxf(0,(size.y-height*factor)/2))
	canvas.custom_minimum_size.y = height*factor
	_rect(%ProfileHeader,Rect2(0,0,width,158 if _compact else 64))
	_rect(%Brand,Rect2(30,9,510,48))
	var navs := [%Trips,%ProfileTab,%Rating,%Notices]
	for i in 4:
		_rect(navs[i],Rect2(16+i*136,86,132,60) if _compact else Rect2(654+i*246,0,242,64))
		navs[i].add_theme_font_size_override("font_size",18 if _compact else 26)
	_rect(body,Rect2(0,0,width,height))
	_rect(%IdentityCard,Rect2(25,215,510,545) if _compact else Rect2(50,175,355,579))
	_rect(%Portrait,Rect2(109,-40,294,360) if _compact else Rect2(22,-53,314,384))
	_rect(%PlayerName,Rect2(30,326,450 if _compact else 305,94))
	%PlayerName.max_lines_visible = 2
	%PlayerName.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_rect(%Role,Rect2(30,419,450 if _compact else 305,35))
	_rect(%Points,Rect2(30,456,270,53))
	_rect(%IdentityRule,Rect2(30,511,450 if _compact else 295,1))
	_rect(%TripsCount,Rect2(30,520,450 if _compact else 300,43))
	if _compact:
		_rect(%PlayerName,Rect2(30,320,450,74))
		_rect(%Role,Rect2(30,397,450,35))
		_rect(%Points,Rect2(30,432,450,53))
		_rect(%IdentityRule,Rect2(30,490,450,1))
		_rect(%TripsCount,Rect2(30,497,450,40))
	var sw := 510.0 if _compact else 788.0
	_rect(%SkillsCard,Rect2(25,782,sw,510) if _compact else Rect2(420,175,sw,495))
	_rect(%Title,Rect2(30,13,sw-60,72))
	_rect(%Subtitle,Rect2(32,88,sw-64,40))
	_rect(%SkillsRule,Rect2(32,129,sw-64,1))
	for i in SKILLS.size():
		var id: String = SKILLS[i][0]
		_rect(get_node("%"+id+"Row"),Rect2(26,149+i*55,sw-52,50))
		_rect(get_node("%"+id+"Name"),Rect2(8,8,242 if _compact else 315,40))
		get_node("%"+id+"Name").add_theme_font_size_override("font_size",22 if _compact else 26)
		_rect(bars[id],Rect2(258 if _compact else 326,16,132 if _compact else 342,24))
		_rect(get_node("%"+id+"Value"),Rect2(sw-110,8,57,40))
		_rect(get_node("%"+id+"Empty"),Rect2(258 if _compact else 326,8,180,40))
	_rect(%SkillsFootRule,Rect2(32,437,sw-64,1))
	_rect(%SkillsNote,Rect2(32,449,sw-64,50))
	_rect(%RecommendationCard,Rect2(25,1312,510,490) if _compact else Rect2(1238,175,384,495))
	var rw := 510.0 if _compact else 384.0
	_rect(%RecTitle,Rect2(30,15,rw-60,62))
	_rect(%RecRule,Rect2(30,82,rw-60,1))
	_rect(%RecommendationArt,Rect2(28,98,rw-56,226))
	_rect(%Recommendation,Rect2(30,334,rw-60,47))
	%Recommendation.add_theme_font_size_override("font_size",27)
	_rect(%RecHint,Rect2(30,380,rw-60,48))
	_rect(%Train,Rect2(30,432,rw-60,58))
	for i in 4:
		var aw := 510.0 if _compact else 288.0
		_rect(get_node("%Award"+str(i)),Rect2(25,1824+i*102,aw,92) if _compact else Rect2(420+i*305,690,aw,145))
		_rect(get_node("%AwardIcon"+str(i)),Rect2(18,8,64,77) if _compact else Rect2(16,17,79,101))
		_rect(get_node("%AwardTitle"+str(i)),Rect2(100,7,390,35) if _compact else Rect2(108,23,172,54))
		get_node("%AwardTitle"+str(i)).add_theme_font_size_override("font_size",22 if _compact else (18 if i == 2 else 20))
		_rect(get_node("%AwardText"+str(i)),Rect2(100,48,390,32) if _compact else Rect2(108,82,172,52))
		get_node("%AwardText"+str(i)).add_theme_font_size_override("font_size",21)
		get_node("%AwardTitle"+str(i)).text = str(AWARDS[i][1]).replace("\n"," ") if _compact else str(AWARDS[i][1])
		if _compact: get_node("%AwardText"+str(i)).text = get_node("%AwardText"+str(i)).text.replace("\n"," ")
	_rect(%Footer,Rect2(0,2240,width,94) if _compact else Rect2(0,875,width,66))
	_rect(%FooterHint,Rect2(50,12,530,40))
	%FooterHint.visible = not _compact
	_rect(%Archive,Rect2(16,17,336,60) if _compact else Rect2(973,6,438,54))
	%Archive.add_theme_font_size_override("font_size",19 if _compact else 24)
	_rect(%Refresh,Rect2(364,17,180,60) if _compact else Rect2(1440,6,182,54))
	_rect(%Status,Rect2(32,165,width-64,50) if _compact else Rect2(50,95,width-100,55))
	_fit_modal()
func present(value: Dictionary) -> void:
	profile = value.duplicate(true)
	body.show()
	%Status.hide()
	%Refresh.disabled = false
	%Archive.disabled = false
	%Archive.refresh()
	%Refresh.refresh()
	%PlayerName.text = str(value.get("display_name","Игрок")).to_upper()
	%PlayerName.add_theme_font_size_override("font_size",40 if %PlayerName.text.length() < 20 else 29)
	%Points.text = "%s очков" % Text.metric(value.get("total_points"))
	%TripsCount.text = "Рейсов завершено: %s" % Text.metric(value.get("completed_trips"))
	targets.clear()
	var maximum := 1.0
	for item in value.get("competencies",[]):
		targets[item.id] = float(item.points)
		maximum = maxf(maximum,float(item.points))
	for spec in SKILLS:
		var id: String = spec[0]
		bars[id].max_value = maximum
		bars[id].visible = targets.has(id)
		get_node("%"+id+"Value").visible = targets.has(id)
		get_node("%"+id+"Value").text = Text.metric(targets.get(id))
		get_node("%"+id+"Empty").visible = not targets.has(id)
		get_node("%"+id+"Details").disabled = not targets.has(id)
	%SkillsNote.text = "Очки лучших рейсов · полосы относительно лучшего навыка"
	for i in 4:
		var item := _award(i)
		var earned := bool(item.get("earned",item.get("unlocked",false)))
		get_node("%AwardIcon"+str(i)).modulate = Color.WHITE if earned else Color("a8aaa5")
		get_node("%AwardText"+str(i)).text = (AWARDS[i][2] if earned else "Пока не получено") if i < 3 else ("Открыт · скоро в игре" if earned else "Откроется позже")
		if _compact: get_node("%AwardText"+str(i)).text = get_node("%AwardText"+str(i)).text.replace("\n"," ")
	%Archive.text = "СОХРАНЁННЫЕ РАЗБОРЫ  ·  %s  ›" % value.get("report_ids",[]).size()
	%Archive.add_theme_font_size_override("font_size",19 if _compact else 24)
	_close_modal(true)
	scroll_vertical = 0
	_apply_bars(1)
	if is_visible_in_tree(): _open()
func _award(index: int) -> Dictionary:
	for item in profile.get("achievements" if index < 3 else "content",[]):
		if item.get("id") == AWARDS[index][0]: return item
	return {}
func _apply_bars(progress: float) -> void:
	for id in bars: bars[id].value = float(targets.get(id,0))*progress
func _visibility() -> void:
	if is_visible_in_tree(): _open()
	else:
		if entry_motion and entry_motion.is_valid(): entry_motion.kill()
		_close_modal(true)
func _open() -> void:
	if _opening: return
	_opening = true
	await get_tree().process_frame
	_opening = false
	if not is_visible_in_tree(): return
	if entry_motion and entry_motion.is_valid(): entry_motion.kill()
	_adapt_layout()
	for b in buttons: b.reduced_motion = reduced_motion
	for g in groups:
		g.modulate.a = 1
		g.scale = Vector2.ONE
	_apply_bars(1)
	if reduced_motion or not body.visible: return
	entry_motion = create_tween().set_ignore_time_scale(true).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in groups.size():
		var g := groups[i]
		g.pivot_offset = g.size*0.5
		g.scale = Vector2.ONE*0.988
		g.modulate.a = 0
		entry_motion.tween_property(g,"modulate:a",1.0,0.38).set_delay(i*0.055)
		entry_motion.tween_property(g,"scale",Vector2.ONE,0.48).set_delay(i*0.055)
	_apply_bars(0)
	entry_motion.tween_method(_apply_bars,0.0,1.0,0.8).set_delay(0.22)
func loading() -> void:
	body.hide()
	_close_modal(true)
	%Status.text = "Загружаем ваш учебный прогресс…"
	%Status.show()
	%Refresh.disabled = true
	%Archive.disabled = true
	%Refresh.refresh()
	%Archive.refresh()
func failed(message: String) -> void:
	body.hide()
	%Status.text = message+"  Нажмите «Обновить»."
	%Status.show()
	%Refresh.disabled = false
	%Refresh.refresh()
func _build_modal() -> void:
	modal = Control.new()
	add_child(modal)
	modal.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = Color(0.06,0.09,0.10,0.82)
	modal.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scrim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _close_modal())
	modal_panel = _panel("DetailsPanel",modal,"paper",24)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation",16)
	modal_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_label("ModalTitle","СОХРАНЁННЫЕ РАЗБОРЫ",head,28,true).size_flags_horizontal = SIZE_EXPAND_FILL
	_button("CloseDetails","×",head,_close_modal).custom_minimum_size.x = 50
	var tabs := HBoxContainer.new()
	_named(tabs,"ArchiveTabs",v)
	_button("ReportsTab","РЕЙСЫ",tabs,_show_archive,"primary").size_flags_horizontal = SIZE_EXPAND_FILL
	_button("BestTab","ЛИЧНЫЕ РЕКОРДЫ",tabs,_show_best).size_flags_horizontal = SIZE_EXPAND_FILL
	modal_scroll = ScrollContainer.new()
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(modal_scroll)
	record_copy = VBoxContainer.new()
	record_copy.size_flags_horizontal = SIZE_EXPAND_FILL
	record_copy.add_theme_constant_override("separation",16)
	modal_scroll.add_child(record_copy)
	_label("RecordTitle","",record_copy,29,true)
	_label("RecordDetail","",record_copy,23)
	var meta := _label("RecordMeta","",record_copy,18)
	meta.add_theme_color_override("font_color",Color("60665f"))
	meta.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_button("OpenReport","ОТКРЫТЬ ОТЧЁТ И РАЗБОР",v,_open_record,"primary")
	var pager := HBoxContainer.new()
	_named(pager,"Pager",v)
	_button("Previous","‹",pager,_move_record.bind(-1)).custom_minimum_size.x = 60
	var count := _label("PageLabel","",pager,21)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.size_flags_horizontal = SIZE_EXPAND_FILL
	_button("Next","›",pager,_move_record.bind(1)).custom_minimum_size.x = 60
	modal.hide()
func _fit_modal() -> void:
	if not is_instance_valid(modal_panel): return
	var w := minf(820,size.x-24)
	var h := minf(540,size.y-32)
	modal_panel.position = Vector2((size.x-w)/2,(size.y-h)/2)
	modal_panel.size = Vector2(w,h)
	modal_panel.set_deferred("size",Vector2(w,h))
	%ModalTitle.add_theme_font_size_override("font_size",21 if size.x < 600 else 28)
	%RecordTitle.add_theme_font_size_override("font_size",24 if size.x < 600 else 29)
	%RecordDetail.add_theme_font_size_override("font_size",20 if size.x < 600 else 23)
	%OpenReport.add_theme_font_size_override("font_size",18 if size.x < 600 else 22)
	%ReportsTab.add_theme_font_size_override("font_size",16 if size.x < 600 else 22)
	%BestTab.add_theme_font_size_override("font_size",16 if size.x < 600 else 22)
func _show_archive() -> void:
	section = "reports"
	records = []
	var ids: Array = profile.get("report_ids",[])
	for i in ids.size():
		records.append({"title":"Сохранённый рейс · %s" % (i+1),"detail":"Посмотрите итоги рейса и разберите каждое решение: выбранный ответ, его последствия и рекомендации для следующей попытки.","meta":"Москва — Санкт-Петербург","target":str(ids[i])})
	if records.is_empty(): records.append({"title":"Ваш первый рейс впереди","detail":"Завершите тренировку — здесь появятся её итоги и подробный разбор решений."})
	_show_records("СОХРАНЁННЫЕ РАЗБОРЫ",true)
func _show_best() -> void:
	section = "best"
	records = []
	var names := {"children-disturb":"Пассажиры с детьми","luggage-in-aisle":"Багаж в проходе","wrong-seat":"Спор о месте","service:blanket-1":"Просьба о пледе","service:table-1":"Помощь со столиком"}
	for item in profile.get("best_results",[]):
		records.append({"title":str(names.get(item.scenario_id,"Учебный сценарий")),"detail":"Личный рекорд: %s очков\n\nОткройте сохранённый рейс, чтобы рассмотреть решения и их последствия." % Text.metric(item.points),"meta":"Лучший сохранённый результат","target":str(item.trip_id)})
	if records.is_empty(): records.append({"title":"Рекордов пока нет","detail":"Они появятся после первой завершённой тренировки."})
	_show_records("ЛИЧНЫЕ РЕКОРДЫ",true)
func _skill_details(id: String) -> void:
	section = "skill"
	var title := ""
	for spec in SKILLS:
		if spec[0] == id: title = spec[1]
	records = [{"title":title,"detail":"%s очков по лучшим результатам сохранённых рейсов.\n\nПолоса показывает этот результат относительно самого сильного навыка в вашем профиле. Это накопленные очки, а не оценка по пятибалльной шкале." % Text.metric(targets.get(id)),"meta":"Повторяйте тренировку и разбирайте решения, чтобы улучшать результат."}]
	_show_records("УЧЕБНЫЙ ПРОГРЕСС")
func _award_details(index: int) -> void:
	section = "award"
	var item := _award(index)
	var earned := bool(item.get("earned",item.get("unlocked",false)))
	var conditions := ["Завершите свой первый рейс.","Устраните угрозы безопасности в рейсе.","Проверьте условия перед обещанием решения пассажиру.","Новый вагон открывается по учебному прогрессу. Играть в нём можно будет в следующем обновлении."]
	var record := {"title":AWARDS[index][1].replace("\n"," "),"detail":("Получено\n\n" if earned else "Пока не получено\n\n")+conditions[index],"meta":str(item.get("earned_at",""))}
	if index == 3: record.detail = ("Открыт в вашем прогрессе\n\n" if earned else "Откроется позже\n\n")+conditions[index]
	if earned and not str(item.get("trip_id","")).is_empty(): record.target = str(item.trip_id)
	records = [record]
	_show_records("ДОСТИЖЕНИЕ" if index < 3 else "НОВЫЙ ВАГОН")
func _show_records(title: String, archive := false) -> void:
	record_page = 0
	%ModalTitle.text = title
	%ArchiveTabs.visible = archive
	%ReportsTab.kind = "primary" if section == "reports" else "secondary"
	%BestTab.kind = "primary" if section == "best" else "secondary"
	%ReportsTab.queue_redraw()
	%BestTab.queue_redraw()
	if modal_motion and modal_motion.is_valid(): modal_motion.kill()
	if not modal.visible:
		previous_focus = get_viewport().gui_get_focus_owner()
		modal.modulate.a = 0 if not reduced_motion else 1
		modal.show()
		%CloseDetails.grab_focus()
	_render_record()
	_fit_modal()
	_fit_modal.call_deferred()
	if not reduced_motion:
		modal_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		modal_motion.tween_property(modal,"modulate:a",1.0,0.24)
func _render_record() -> void:
	var record: Dictionary = records[record_page]
	%RecordTitle.text = str(record.get("title",""))
	%RecordDetail.text = str(record.get("detail",""))
	%RecordMeta.text = str(record.get("meta",""))
	%OpenReport.visible = record.has("target")
	%Pager.visible = section in ["reports","best"]
	%Previous.disabled = record_page == 0
	%Next.disabled = record_page == records.size()-1
	%Previous.refresh()
	%Next.refresh()
	%PageLabel.text = "%s из %s" % [record_page+1,records.size()]
	modal_scroll.scroll_vertical = 0
	if page_motion and page_motion.is_valid(): page_motion.kill()
	record_copy.modulate.a = 1 if reduced_motion else 0.25
	if not reduced_motion:
		page_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		page_motion.tween_property(record_copy,"modulate:a",1.0,0.22)
	_wire_focus()
func _wire_focus() -> void:
	var focusables: Array[Control] = []
	for n in modal.find_children("*","Button",true,false):
		if n.is_visible_in_tree() and not n.disabled: focusables.append(n)
	for i in focusables.size():
		focusables[i].focus_next = focusables[(i+1)%focusables.size()].get_path()
		focusables[i].focus_previous = focusables[(i-1+focusables.size())%focusables.size()].get_path()
func _move_record(direction: int) -> void:
	var next := clampi(record_page+direction,0,records.size()-1)
	if next == record_page: return
	record_page = next
	_render_record()
func _open_record() -> void:
	if records.is_empty(): return
	var target := str(records[record_page].get("target",""))
	if target.is_empty(): return
	_close_modal(true)
	report_requested.emit(target)
func _close_modal(immediate := false) -> void:
	if not is_instance_valid(modal): return
	if modal_motion and modal_motion.is_valid(): modal_motion.kill()
	if immediate or reduced_motion:
		modal.hide()
		if not immediate and is_instance_valid(previous_focus): previous_focus.grab_focus()
		return
	if not modal.visible: return
	modal_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	modal_motion.tween_property(modal,"modulate:a",0.0,0.18)
	modal_motion.tween_callback(func():
		modal.hide()
		if is_instance_valid(previous_focus): previous_focus.grab_focus())
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	if modal.visible:
		if event.keycode == KEY_ESCAPE: _close_modal()
		elif event.keycode == KEY_LEFT: _move_record(-1)
		elif event.keycode == KEY_RIGHT: _move_record(1)
		else: return
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		replay_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_TAB and get_viewport().gui_get_focus_owner() == null:
		%Trips.grab_focus()
		get_viewport().set_input_as_handled()
