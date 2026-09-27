extends Control
signal list_requested(page: int)
signal replay_requested
signal profile_requested
signal leaderboard_requested
signal report_requested(trip_id: String)
const Paper = preload("res://scripts/report/panel.gd")
const Action = preload("res://scripts/notifications/action_button.gd")
const Nav = preload("res://scripts/profile/nav_button.gd")
const Card = preload("res://scripts/notifications/event_card.gd")
const ART = preload("res://assets/notifications/concept-atlas.png")
var requested_page := 1
var reduced_motion := false
var entries: Array = []
var remote: Array = []
var profile: Dictionary = {}
var selected_id := ""
var selected_index := -1
var total := 0
var busy := false
var has_response := false
var load_failed := false
var cards: Array[Button] = []
var buttons: Array[Button] = []
var scroller: ScrollContainer
var canvas: Control
var stage: Control
var detail: Control
var list_scroll: ScrollContainer
var list_box: VBoxContainer
var copy_scroll: ScrollContainer
var copy_box: VBoxContainer
var transition: Tween
var entrance: Tween
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
func _label(id: String, text: String, p: Node, fs := 27, heading := false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size",fs)
	if heading: l.add_theme_font_override("font",get_theme_font("font","Heading"))
	_named(l,id,p)
	return l
func _panel(id: String, p: Node, palette := "paper") -> Control:
	var panel := Paper.new()
	panel.palette = palette
	panel.cut = 28
	panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	_named(panel,id,p)
	var content := Control.new()
	content.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(content)
	return content
func _button(id: String, text: String, p: Node, cb: Callable, kind := "secondary", nav := false) -> Button:
	var b: Button = Nav.new() if nav else Action.new()
	b.kind = kind
	b.text = text
	b.clip_text = true
	b.custom_minimum_size = Vector2(44,52)
	_named(b,id,p)
	b.pressed.connect(cb)
	buttons.append(b)
	return b
func _art(id: String, region: Rect2, p: Node) -> TextureRect:
	var t := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = ART
	atlas.region = region
	atlas.filter_clip = true
	t.texture = atlas
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.mouse_filter = MOUSE_FILTER_IGNORE
	_named(t,id,p)
	return t
func _ready() -> void:
	clip_contents = true
	var bg := TextureRect.new()
	bg.texture = preload("res://assets/menu/valley.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color("b9bfb2")
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color(0.64,0.68,0.63,0.91)
	veil.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(veil)
	veil.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
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
	_art("Landscape",Rect2(0,760,646,106),stage)
	var hc := _panel("NoticeHeader",stage,"dark")
	%NoticeHeader.cut = 0
	_label("Brand","НАЧАЛЬНИК РЕЙСА",hc,34,true).add_theme_color_override("font_color",Color("eee7d8"))
	_label("Tagline","ЛЮДИ. ВАГОНЫ. РЕШЕНИЯ.",hc,17).add_theme_color_override("font_color",Color("bfc4bf"))
	for spec in [["Home","ГЛАВНАЯ",func(): replay_requested.emit()],["ProfileNav","ПРОФИЛЬ",func(): profile_requested.emit()],["RatingNav","РЕЙТИНГ",func(): leaderboard_requested.emit()],["NoticesNav","УВЕДОМЛЕНИЯ",func(): _on_refresh()]]:
		_button(spec[0],spec[1],hc,spec[2],"primary" if spec[0] == "NoticesNav" else "secondary",true).add_theme_font_size_override("font_size",25)
	_art("TrainMark",Rect2(1394,11,236,58),hc)
	_label("ScreenTitle","УВЕДОМЛЕНИЯ",stage,49,true)
	list_scroll = ScrollContainer.new()
	_named(list_scroll,"ListScroll",stage)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation",12)
	list_scroll.add_child(list_box)
	_label("ListState","События вашего учебного прогресса",stage,28)
	_button("Previous","‹",stage,_on_page.bind(-1)).add_theme_font_size_override("font_size",34)
	_button("Next","›",stage,_on_page.bind(1)).add_theme_font_size_override("font_size",34)
	_label("PageLabel","",stage,23)
	detail = _panel("DetailPanel",stage)
	_label("DetailTitle","ВАШИ СОБЫТИЯ",detail,52,true)
	_art("Medal",Rect2(1540,118,66,81),detail)
	_art("Hero",Rect2(689,207,921,330),detail)
	var tag := _panel("TagPlate",detail,"sage")
	%TagPlate.cut = 12
	_label("DetailTag","ЖУРНАЛ ПРОГРЕССА",tag,32,true)
	copy_scroll = ScrollContainer.new()
	_named(copy_scroll,"CopyScroll",detail)
	copy_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	copy_box = VBoxContainer.new()
	copy_box.size_flags_horizontal = SIZE_EXPAND_FILL
	copy_box.add_theme_constant_override("separation",12)
	copy_scroll.add_child(copy_box)
	_label("DetailLead","Здесь будут важные события ваших рейсов.",copy_box,29,true)
	_label("DetailBody","Завершите учебный рейс, чтобы увидеть свой прогресс.",copy_box,28)
	_label("DetailDate","",copy_box,21).add_theme_color_override("font_color",Color("61665e"))
	%DetailDate.hide()
	_button("Secondary","РЕЙС СКОРО",detail,_secondary).add_theme_font_size_override("font_size",29)
	_button("Primary","К ТРЕНИРОВКЕ  ›",detail,_primary,"primary").add_theme_font_size_override("font_size",31)
	var fc := _panel("NoticeFooter",stage,"dark")
	%NoticeFooter.cut = 0
	_button("Back","‹  ГЛАВНАЯ",fc,func(): replay_requested.emit(),"secondary",true)
	_button("ProfileFooter","ПРОФИЛЬ",fc,func(): profile_requested.emit(),"secondary",true)
	_button("Refresh","ОБНОВИТЬ",fc,_on_refresh,"secondary",true)
	_label("FooterMotto","ДВИЖЕНИЕ ДЕЛАЕТ ЛЮДЕЙ БЛИЖЕ",fc,21).add_theme_color_override("font_color",Color("b6bfba"))
	_label("Status","",stage,23).add_theme_color_override("font_color",Color("253b40"))
	resized.connect(_adapt_layout)
	visibility_changed.connect(_visibility)
	_adapt_layout()
	_show_empty("Пока нет уведомлений","После завершения рейса здесь появятся новые события.")

func _adapt_layout() -> void:
	if not is_instance_valid(stage): return
	_compact = size.x < 900
	var width := 560.0 if _compact else 1672.0
	var height := 1840.0 if _compact else 941.0
	var factor := maxf(0.1,(size.x-(12 if _compact else 0))/width)
	if not _compact: factor = minf(factor,size.y/height)
	stage.scale = Vector2.ONE*factor
	stage.size = Vector2(width,height)
	stage.position = Vector2(maxf(0,(size.x-width*factor)/2),maxf(0,(size.y-height*factor)/2))
	canvas.custom_minimum_size.y = height*factor
	_rect(%NoticeHeader,Rect2(0,0,width,148 if _compact else 80))
	_rect(%Brand,Rect2(36,3,485,51))
	_rect(%Tagline,Rect2(38,55,470,24))
	for i in 4:
		_rect([%Home,%ProfileNav,%RatingNav,%NoticesNav][i],Rect2(10+i*136,86,134,62) if _compact else Rect2(552+i*198,0,194,80))
		[%Home,%ProfileNav,%RatingNav,%NoticesNav][i].add_theme_font_size_override("font_size",19 if _compact else 25)
	%TrainMark.visible = not _compact
	_rect(%TrainMark,Rect2(1400,11,231,57))
	_rect(%ScreenTitle,Rect2(30,170,500,70) if _compact else Rect2(64,95,556,72))
	_rect(%Landscape,Rect2(0,715,648,153))
	%Landscape.visible = not _compact
	_rect(list_scroll,Rect2(24,254,512,444) if _compact else Rect2(38,166,598,606))
	_rect(%ListState,Rect2(42,300,460,240) if _compact else Rect2(65,207,520,270))
	_rect(%Previous,Rect2(24,718,64,60) if _compact else Rect2(40,778,68,54))
	_rect(%Next,Rect2(472,718,64,60) if _compact else Rect2(562,778,68,54))
	_rect(%PageLabel,Rect2(104,735,346,40) if _compact else Rect2(125,790,420,40))
	%PageLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(%DetailPanel,Rect2(24,808,512,882) if _compact else Rect2(650,101,990,734))
	var dw := 512.0 if _compact else 990.0
	_rect(%DetailTitle,Rect2(28,22,dw-110,118) if _compact else Rect2(38,16,830,88))
	%DetailTitle.add_theme_font_size_override("font_size",34 if _compact else 51)
	%DetailTitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _compact else TextServer.AUTOWRAP_OFF
	%DetailTitle.clip_text = true
	%DetailTitle.max_lines_visible = 2 if _compact else 1
	%DetailTitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_rect(%Medal,Rect2(dw-90,24,58,72))
	_rect(%Hero,Rect2(28,155,dw-56,220) if _compact else Rect2(38,105,920,332))
	_rect(%TagPlate,Rect2(28,392,456,58) if _compact else Rect2(40,448,440,58))
	_rect(%DetailTag,Rect2(24,5,410,47))
	%DetailTag.add_theme_font_size_override("font_size",27 if _compact else 32)
	_rect(copy_scroll,Rect2(30,472,dw-60,220) if _compact else Rect2(42,520,902,90))
	if not _compact and (selected_index < 0 or entries[selected_index].kind != "future"):
		_rect(%Hero,Rect2(38,105,920,222))
		_rect(%TagPlate,Rect2(40,342,510,58))
		_rect(copy_scroll,Rect2(42,414,902,192))
	_rect(%Secondary,Rect2(28,712,dw-56,62) if _compact else Rect2(40,618,404,90))
	_rect(%Primary,Rect2(28,790,dw-56,64) if _compact else Rect2(470,618,484,90))
	%Primary.add_theme_font_size_override("font_size",28 if _compact else 31)
	_rect(%Status,Rect2(28,1702,504,60) if _compact else Rect2(662,842,960,26))
	_rect(%NoticeFooter,Rect2(0,1770,width,70) if _compact else Rect2(0,868,width,73))
	_rect(%Back,Rect2(12,2,176,66))
	_rect(%ProfileFooter,Rect2(194,2,166,66))
	_rect(%Refresh,Rect2(366 if _compact else 390,2,182,66))
	%FooterMotto.visible = not _compact
	_rect(%FooterMotto,Rect2(1200,24,432,36))
	for c in cards: c._layout()

func present_profile(value: Dictionary) -> void:
	profile = value.duplicate(true)
	if has_response and not busy and not load_failed: _rebuild()
func loading() -> void:
	busy = true
	load_failed = false
	%Refresh.disabled = true
	%NoticesNav.disabled = true
	%Status.text = "Загружаем события…"
	_show_empty("ЗАГРУЖАЕМ СОБЫТИЯ","Ваш журнал скоро появится здесь.")
func failed(message: String) -> void:
	busy = false
	load_failed = true
	%Refresh.disabled = false
	%NoticesNav.disabled = false
	%Status.text = ""
	_show_empty("НЕ УДАЛОСЬ ЗАГРУЗИТЬ",message)
	%Primary.text = "ПОВТОРИТЬ ЗАГРУЗКУ  ›"
	%Secondary.text = "НА ГЛАВНУЮ"
	%Secondary.disabled = false
func present(value: Dictionary) -> void:
	remote = value.get("notifications",[]).duplicate(true)
	requested_page = int(value.get("page",1))
	total = int(value.get("total",remote.size()))
	busy = false
	has_response = true
	load_failed = false
	%Refresh.disabled = false
	%NoticesNav.disabled = false
	%Status.text = ""
	_rebuild()
func _rebuild() -> void:
	entries.clear()
	for item: Dictionary in remote:
		var entry := item.duplicate(true)
		var future: bool = item.get("carriage_id") == "carriage-3" and item.get("content_status") == "future_content"
		entry["kind"] = "future" if future else "event"
		entry["caption"] = "Новая зона\nответственности" if future else str(item.get("title","Событие рейса"))
		entry["subtitle"] = "Открыт вагон «Комфорт»" if future else str(item.get("message",""))
		entries.append(entry)
	# Context cards come from confirmed profile progress, never from a fabricated event feed.
	if requested_page == 1 and not profile.is_empty():
		entries.append({"id":"practice","kind":"practice","caption":"Рекомендована\nтренировка","subtitle":"Проверка условий","title":"ПРОВЕРКА УСЛОВИЙ","message":"Уточните свободные места и условия размещения, прежде чем давать обещание пассажиру. Повторите ситуации в стандартном вагоне — в спокойном темпе, с разбором каждого решения."})
		var earned: Array = profile.get("achievements",[]).filter(func(a): return a.get("earned",false))
		earned.sort_custom(func(a,b): return str(a.get("earned_at","")) > str(b.get("earned_at","")))
		# One featured earned achievement, with access to all achievements through the profile.
		if not earned.is_empty():
			var award: Dictionary = earned[0]
			for a: Dictionary in earned:
				if a.get("id") == "safety_resolved": award = a
			entries.append({"id":"award:"+str(award.id),"kind":"award","caption":"Новое достижение","subtitle":award.name,"title":str(award.name).to_upper(),"message":_award_description(str(award.id)),"trip_id":award.get("trip_id",""),"created_at":award.get("earned_at","")})
	_clear_cards()
	%ListState.visible = entries.is_empty()
	%Previous.visible = total > 3
	%Next.visible = total > 3
	%Previous.disabled = requested_page <= 1
	%Next.disabled = requested_page*3 >= total
	%PageLabel.text = "Страница %s из %s" % [requested_page,maxi(1,ceili(total/3.0))] if total > 3 else "Выберите событие, чтобы узнать больше"
	if entries.is_empty():
		_show_empty("ПОКА НЕТ УВЕДОМЛЕНИЙ","Завершите учебный рейс. Здесь появятся новые события и достижения.")
		return
	var index := 0
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var c := Card.new()
		c.variant = 1 if entry.kind == "practice" else (2 if entry.kind == "award" else 0)
		c.caption = entry.caption
		c.reduced_motion = reduced_motion
		c.glyph = load("res://assets/notifications/award.svg") if entry.kind == "award" else load("res://assets/menu/"+str({"future":"lock","event":"bell","practice":"book"}.get(entry.kind,"bell"))+".svg")
		c.custom_minimum_size = Vector2(0,190)
		c.size_flags_horizontal = SIZE_EXPAND_FILL
		list_box.add_child(c)
		c.subtitle.text = entry.subtitle
		c.accessibility_name = entry.caption.replace("\n"," ")+". "+entry.subtitle
		c.tooltip_text = c.accessibility_name if entry.kind == "event" else ""
		c.pressed.connect(_select.bind(i))
		cards.append(c)
		if not reduced_motion and is_visible_in_tree():
			c.modulate.a = 0
			var reveal := c.create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			reveal.tween_property(c,"modulate:a",1.0,0.28).set_delay(i*0.055)
		if str(entry.id) == selected_id: index = i
	_select(index,true)
	if not reduced_motion and is_visible_in_tree():
		detail.modulate.a = 0
		transition = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		transition.tween_property(detail,"modulate:a",1.0,0.32)
	_adapt_layout()
func _award_description(id: String) -> String:
	return str({"safety_resolved":"Вы успешно устранили угрозу безопасности в учебном рейсе. Внимание к проходам, багажу и своевременным действиям помогает сделать поездку спокойной для всех.","first_trip":"Первый учебный рейс завершён. Его результат сохранён: можно вернуться к разбору и посмотреть, как ваши решения повлияли на поездку.","checked_before_promise":"Вы проверили условия до того, как дали обещание пассажиру. Это помогает находить выполнимые решения и сохранять доверие."}.get(id,"Достижение сохранено в вашем профиле."))
func _clear_cards() -> void:
	for c in cards:
		list_box.remove_child(c)
		c.queue_free()
	cards.clear()
func _show_empty(title: String, message: String) -> void:
	if transition and transition.is_valid(): transition.kill()
	detail.modulate.a = 1.0
	_clear_cards()
	selected_index = -1
	%ListState.visible = true
	%ListState.text = "Получаем события…" if busy else ("Проверьте подключение и повторите загрузку." if load_failed else "Новые события появятся после учебного рейса.")
	%Previous.hide()
	%Next.hide()
	%PageLabel.text = ""
	%DetailTitle.text = title
	%DetailLead.text = message
	%DetailBody.text = ""
	%DetailDate.text = ""
	%DetailTag.text = "ЖУРНАЛ ПРОГРЕССА"
	%Hero.modulate = Color(0.75,0.77,0.72,0.65)
	%Medal.hide()
	%Secondary.text = "РЕЙС СКОРО"
	%Secondary.disabled = true
	%Primary.text = "К ТРЕНИРОВКЕ  ›"
	%Primary.disabled = busy
	copy_scroll.scroll_vertical = 0
	_adapt_layout()
func _select(index: int, immediate := false) -> void:
	if index < 0 or index >= entries.size(): return
	selected_index = index
	selected_id = str(entries[index].id)
	for i in cards.size(): cards[i].choose(i == index,immediate)
	if transition and transition.is_valid(): transition.kill()
	if immediate or reduced_motion:
		_apply_detail()
		detail.modulate.a = 1.0
	else:
		# Last selection wins even while a previous card is fading out.
		transition = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		transition.tween_property(detail,"modulate:a",0.0,0.09)
		transition.tween_callback(_apply_detail)
		transition.tween_property(detail,"modulate:a",1.0,0.22)
	if _compact and not immediate:
		scroller.set_deferred("scroll_vertical",roundi(800*stage.scale.y))
func _apply_detail() -> void:
	if selected_index < 0 or selected_index >= entries.size(): return
	var item: Dictionary = entries[selected_index]
	_adapt_layout()
	var future: bool = item.kind == "future"
	%DetailTitle.text = "ВАГОН «КОМФОРТ» ОТКРЫТ" if future else str(item.get("title",item.caption)).to_upper()
	%DetailTitle.add_theme_font_size_override("font_size",34 if _compact else (43 if %DetailTitle.text.length() > 30 else 51))
	%DetailTag.text = str({"future":"БУДУЩИЙ КОНТЕНТ","practice":"УЧЕБНЫЙ РЕЙС","award":"ДОСТИЖЕНИЕ ПОЛУЧЕНО","event":"СОБЫТИЕ РЕЙСА"}[item.kind])
	%DetailLead.text = "Зона открыта в прогрессе. Учебный рейс для неё пока недоступен." if future else ("Уточняйте условия, прежде чем обещать" if item.kind == "practice" else ("Ваше решение стало частью прогресса" if item.kind == "award" else str(item.get("title",""))))
	%DetailBody.text = "Пока можно повторить ситуации в стандартном вагоне." if future else str(item.get("message",""))
	%DetailDate.text = ""
	if item.get("created_at","") != "":
		var date := str(item.created_at).left(10).split("-")
		if date.size() == 3: %Status.text = "Сохранено %s.%s.%s" % [date[2],date[1],date[0]]
	else: %Status.text = "Рекомендация для вашей следующей тренировки"
	%Hero.modulate = Color.WHITE
	%Hero.texture = _hero_texture(item.kind)
	%Medal.visible = item.kind in ["future","award"]
	%Primary.disabled = false
	%Primary.text = "ОТКРЫТЬ РАЗБОР  ›" if _has_report(item) else ("НАЧАТЬ ТРЕНИРОВКУ  ›" if item.kind == "practice" else "ПОВТОРИТЬ ТРЕНИРОВКУ  ›")
	%Secondary.text = "РЕЙС СКОРО" if future else "МОЙ ПРОФИЛЬ"
	%Secondary.disabled = future
	copy_scroll.scroll_vertical = 0
func _hero_texture(kind: String) -> Texture2D:
	var atlas := AtlasTexture.new()
	if kind in ["practice","award"]:
		atlas.atlas = preload("res://assets/debrief/seat.jpg") if kind == "practice" else preload("res://assets/debrief/luggage.jpg")
		atlas.region = Rect2(0,120,atlas.atlas.get_width(),440)
	else:
		atlas.atlas = ART
		atlas.region = Rect2(689,207,921,330)
	atlas.filter_clip = true
	return atlas
func _has_report(item: Dictionary) -> bool:
	var id := str(item.get("trip_id",""))
	return item.get("kind") == "award" and id.length() == 32 and id.is_valid_hex_number()
func _primary() -> void:
	if busy: return
	if load_failed:
		_on_refresh()
		return
	if selected_index >= 0 and _has_report(entries[selected_index]):
		report_requested.emit(str(entries[selected_index].trip_id))
	else: replay_requested.emit()
func _secondary() -> void:
	if load_failed: replay_requested.emit()
	else: profile_requested.emit()
func _on_refresh() -> void:
	if not busy: list_requested.emit(requested_page)
func _on_page(delta: int) -> void:
	if busy: return
	var page := requested_page+delta
	if page < 1 or (page-1)*3 >= total: return
	list_requested.emit(page)
func _visibility() -> void:
	if not is_node_ready(): return
	if entrance and entrance.is_valid(): entrance.kill()
	if not is_visible_in_tree():
		if transition and transition.is_valid(): transition.kill()
		if selected_index >= 0: _apply_detail()
		detail.modulate.a = 1
		stage.modulate.a = 1
		return
	for b in buttons: b.reduced_motion = reduced_motion
	for c in cards: c.reduced_motion = reduced_motion
	stage.modulate.a = 1
	if not reduced_motion:
		stage.modulate.a = 0
		entrance = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		entrance.tween_property(stage,"modulate:a",1.0,0.32)
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or busy or not event.is_pressed() or event.is_echo(): return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		var delta := 1 if event.is_action_pressed("ui_right") else -1
		if not cards.is_empty():
			var index := clampi(selected_index+delta,0,cards.size()-1)
			_select(index)
			cards[index].grab_focus()
			get_viewport().set_input_as_handled()
