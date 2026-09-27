extends Control
signal debrief_requested(request_id: String)
signal report_requested(trip_id: String)
signal refresh_requested
signal replay_requested
signal profile_requested
const Text = preload("res://scripts/server_text.gd")
const Crew = preload("res://scripts/crew_state.gd")
const Progress = preload("res://scripts/progress_data.gd")
const Paper = preload("res://scripts/report/panel.gd")
const ReviewButton = preload("res://scripts/debrief/review_button.gd")
const CardHit = preload("res://scripts/report/card_hit.gd")
const Icon = preload("res://scripts/report/icon.gd")
const ATLAS = preload("res://assets/report/concept-atlas.png")
var report: Dictionary = {}
var section := "incidents"
var reduced_motion := false
var scroller: ScrollContainer
var canvas: Control
var stage: Control
var hero: TextureRect
var groups: Array[Control] = []
var positions: Dictionary = {}
var buttons: Array[Button] = []
var modal: Control
var modal_panel: PanelContainer
var modal_tabs: GridContainer
var modal_scroll: ScrollContainer
var previous_focus: Control
var records: Array = []
var saved_reports: Array = []
var record_page := 0
var section_buttons: Dictionary = {}
var entry_motion: Tween
var modal_motion: Tween
var record_motion: Tween
var metric_targets: Dictionary = {}
var _opening := false
var _compact := false
var _locked := false
var scroll_vertical: int:
	get: return scroller.scroll_vertical if is_instance_valid(scroller) else 0
	set(value):
		if is_instance_valid(scroller): scroller.scroll_vertical = value

func _named(node: Node, title: String, parent: Node) -> void:
	node.name = title
	parent.add_child(node)
	node.owner = self
	node.unique_name_in_owner = true
func _rect(node: Control, r: Rect2) -> void:
	node.position = r.position
	node.size = r.size
	# Autowrap and container minima settle after their width is assigned.
	node.set_deferred("size",r.size)
func _label(title: String, value: String, parent: Node, fs := 27, heading := false) -> Label:
	var l := Label.new()
	_named(l,title,parent)
	l.text = value
	l.mouse_filter = MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size",fs)
	if heading: l.add_theme_font_override("font",get_theme_font("font","Heading"))
	return l
func _paper(title: String, parent: Node, palette := "paper", pad := 0) -> PanelContainer:
	var p := Paper.new()
	p.palette = palette
	_named(p,title,parent)
	var style := StyleBoxEmpty.new()
	style.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel",style)
	return p
func _group(title: String, r: Rect2, palette := "paper") -> Control:
	var p := _paper(title,stage,palette)
	_rect(p,r)
	var c := Control.new()
	p.add_child(c)
	groups.append(p)
	positions[title] = r
	return c
func _icon(parent: Node, symbol: String, r: Rect2, color := Color("3d5845")) -> Control:
	var icon := Icon.new()
	icon.symbol = symbol
	icon.color = color
	parent.add_child(icon)
	_rect(icon,r)
	return icon
func _button(title: String, value: String, parent: Node, callback: Callable, kind := "secondary") -> Button:
	var b := ReviewButton.new()
	b.kind = kind
	b.text = value
	b.custom_minimum_size = Vector2(44,52)
	_named(b,title,parent)
	b.pressed.connect(callback)
	buttons.append(b)
	return b
func _art(parent: Node, region: Rect2, r: Rect2) -> TextureRect:
	var atlas := AtlasTexture.new()
	atlas.atlas = ATLAS
	atlas.region = region
	atlas.filter_clip = true
	var t := TextureRect.new()
	t.texture = atlas
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(t)
	_rect(t,r)
	return t
func _ready() -> void:
	clip_contents = true
	var bg := ColorRect.new()
	bg.color = Color("26363d")
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroller = ScrollContainer.new()
	add_child(scroller)
	scroller.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.follow_focus = true
	canvas = Control.new()
	canvas.size_flags_horizontal = SIZE_EXPAND_FILL
	canvas.size_flags_vertical = SIZE_EXPAND_FILL
	scroller.add_child(canvas)
	stage = Control.new()
	canvas.add_child(stage)
	stage.size = Vector2(1672,941)
	var backdrop := ColorRect.new()
	backdrop.color = Color("56635e")
	backdrop.mouse_filter = MOUSE_FILTER_IGNORE
	stage.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# Sample illustration-only regions; all report UI and values are native Controls.
	hero = _art(stage,Rect2(854,0,818,393),Rect2(854,0,818,393))
	_art(stage,Rect2(1500,393,172,103),Rect2(1500,393,172,103))
	_art(stage,Rect2(1395,510,277,297),Rect2(1395,510,277,297))
	var h := _group("Header",Rect2(0,0,915,134),"dark")
	%Header.cut = 0
	_rect(_label("Title","РЕЙС ЗАВЕРШЁН",h,72,true),Rect2(60,0,825,91))
	%Title.add_theme_color_override("font_color",get_theme_color("paper","Palette"))
	_rect(_label("Subtitle","Москва — Санкт-Петербург · Рейс 01",h,29),Rect2(63,91,795,40))
	%Subtitle.add_theme_color_override("font_color",Color("d0cec3"))
	_build_metric("Loyalty","ЛОЯЛЬНОСТЬ","people",Rect2(60,154,394,220))
	_build_metric("Safety","БЕЗОПАСНОСТЬ","shield",Rect2(471,154,381,220))
	var stats := _group("Stats",Rect2(60,393,1440,116))
	var stats_margin := MarginContainer.new()
	stats.add_child(stats_margin)
	stats_margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	stats_margin.add_theme_constant_override("margin_left",38)
	stats_margin.add_theme_constant_override("margin_right",38)
	stats_margin.add_theme_constant_override("margin_top",4)
	stats_margin.add_theme_constant_override("margin_bottom",4)
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation",28)
	stats_margin.add_child(stats_row)
	for i in 3:
		if i > 0:
			var line := VSeparator.new()
			line.custom_minimum_size = Vector2(2,78)
			line.size_flags_vertical = SIZE_SHRINK_CENTER
			stats_row.add_child(line)
		var column := HBoxContainer.new()
		column.size_flags_horizontal = SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation",46)
		_named(column,"StatColumn"+str(i),stats_row)
		var color: Color = [Color("405b46"),Color("8c4538"),Color("85622e")][i]
		var icon := _icon(column,["document","document","star"][i],Rect2(0,0,76,76),color)
		icon.custom_minimum_size = Vector2(76,76)
		icon.size_flags_vertical = SIZE_SHRINK_CENTER
		_named_icon(icon,"StatIcon"+str(i))
		var copy := VBoxContainer.new()
		copy.add_theme_constant_override("separation",0)
		copy.size_flags_horizontal = SIZE_EXPAND_FILL
		column.add_child(copy)
		_label(["SolvedCaption","MissedCaption","PointsCaption"][i],["Решено","Пропущено","Очки"][i],copy,25).autowrap_mode = TextServer.AUTOWRAP_OFF
		var l := _label(["Solved","Missed","Points"][i],"—",copy,55,true)
		l.add_theme_color_override("font_color",color)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
	_build_summary("Crew","КООРДИНАЦИЯ БРИГАДЫ",Rect2(60,524,649,182),Rect2(88,545,136,138),"events")
	_build_summary("Decisions","РЕШЕНИЯ В СИТУАЦИЯХ",Rect2(727,524,658,182),Rect2(754,546,158,146),"incidents")
	var tip := _group("Training",Rect2(60,720,1002,78),"gold")
	_icon(tip,"training",Rect2(29,13,65,52),Color("25363b"))
	_rect(_label("Recommendation","",tip,26),Rect2(123,10,851,58))
	%Recommendation.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	%Recommendation.minimum_size_changed.connect(_adapt_layout.call_deferred)
	_card_hit("TrainingDetails",tip,"training")
	var seal := _group("Seal",Rect2(1076,720,309,78))
	_icon(seal,"shield",Rect2(22,10,56,58))
	_rect(_label("SealText","БЕЗОПАСНЫЙ РЕЙС",seal,25,true),Rect2(91,10,195,58))
	%SealText.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var footer := _group("Footer",Rect2(0,808,1672,133),"dark")
	%Footer.cut = 0
	var actions := BoxContainer.new()
	_named(actions,"Actions",footer)
	actions.add_theme_constant_override("separation",28)
	_rect(actions,Rect2(54,18,1342,82))
	for spec in [["Debrief","РАЗБОР РЕШЕНИЙ",_on_debrief,"secondary",435],["Replay","ПОВТОРИТЬ ТРЕНИРОВКУ",_on_replay,"primary",505],["Profile","К ПРОФИЛЮ",func(): profile_requested.emit(),"secondary",346]]:
		var b := _button(spec[0],spec[1],actions,spec[2],spec[3])
		b.custom_minimum_size.x = spec[4]
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size",25)
		_icon(b,{"Debrief":"document","Replay":"repeat","Profile":"profile"}[spec[0]],Rect2(27,21,42,42),Color("24343c") if spec[3] == "primary" else Color("e9e2d3"))
	var archive := _button("Archive","АРХИВ",footer,_select_section.bind("archive"))
	_rect(archive,Rect2(1432,31,180,58))
	archive.add_theme_font_size_override("font_size",20)
	_build_modal()
	visibility_changed.connect(_visibility)
	resized.connect(_adapt_layout)
	_adapt_layout()
	%Title.text = "ИТОГИ РЕЙСА"
	

func _build_metric(id: String, caption: String, symbol: String, r: Rect2) -> void:
	var c := _group(id+"Panel",r)
	_rect(_label(id+"Caption",caption,c,33,true),Rect2(31,13,330,51))
	_icon(c,symbol,Rect2(42,68,89,82),Color("4b5f57") if id == "Loyalty" else Color("2d414c"))
	var n := _label(id,"—",c,89,true)
	n.add_theme_color_override("font_color",Color("304734"))
	_rect(n,Rect2(178,44,193,120))
	var bar := ProgressBar.new()
	_named(bar,id+"Bar",c)
	bar.show_percentage = false
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color("b8b5a8")
	bar.add_theme_stylebox_override("background",track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("465f49")
	bar.add_theme_stylebox_override("fill",fill)
	_rect(bar,Rect2(31,156,r.size.x-61,20))
	_rect(_label(id+"Note","",c,21),Rect2(31,181,r.size.x-50,32))
	if id == "Safety":
		var inspect := _card_hit("InspectSafety",c,"violations")
		inspect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		inspect.tooltip_text = "Посмотреть критические нарушения"
		inspect.accessibility_name = "Посмотреть критические нарушения"

func _build_summary(id: String, caption: String, r: Rect2, region: Rect2, target: String) -> void:
	var c := _group(id+"Panel",r)
	_art(c,region,Rect2(27,21,135,138))
	_rect(_label(id+"Caption",caption,c,30,true),Rect2(180,12,r.size.x-200,47))
	var line := ColorRect.new()
	line.color = Color("a5a89b")
	line.mouse_filter = MOUSE_FILTER_IGNORE
	c.add_child(line)
	_rect(line,Rect2(180,65,r.size.x-208,2))
	for i in 2:
		var icon := _icon(c,"check",Rect2(186,81+i*42,36,36))
		_named_icon(icon,id+"Icon"+str(i))
		_rect(_label(id+"Line"+str(i),"",c,25),Rect2(236,81+i*42,r.size.x-263,42))
	var tag := _label(id+"Hint","ПОДРОБНЕЕ  ›",c,16,true)
	tag.add_theme_color_override("font_color",get_theme_color("paper","Palette"))
	var plate := StyleBoxFlat.new()
	plate.bg_color = get_theme_color("dark","Palette")
	plate.set_content_margin_all(0)
	tag.add_theme_stylebox_override("normal",plate)
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_constant_override("line_spacing",0)
	_rect(tag,Rect2(27,126,135,30))
	_card_hit(id+"Details",c,target)
func _card_hit(id: String, parent: Control, target: String) -> Button:
	var b := CardHit.new()
	_named(b,id,parent)
	b.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	b.accessibility_name = "Подробнее: "+str({"events":"координация бригады","incidents":"решения в ситуациях","violations":"критические нарушения","training":"следующая тренировка"}.get(target,target))
	b.pressed.connect(_select_section.bind(target))
	buttons.append(b)
	return b
func _named_icon(icon: Control, id: String) -> void:
	icon.name = id
	icon.owner = self
	icon.unique_name_in_owner = true

func _build_modal() -> void:
	modal = Control.new()
	add_child(modal)
	modal.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = Color(0.05,0.08,0.10,0.86)
	modal.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scrim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _close_modal())
	modal_panel = _paper("ModalPanel",modal,"paper",24)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation",14)
	modal_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := _label("ModalTitle","ПОДРОБНОСТИ РЕЙСА",head,30,true)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	_button("CloseDetails","ЗАКРЫТЬ  ×",head,_close_modal).custom_minimum_size.x = 142
	modal_tabs = GridContainer.new()
	modal_tabs.columns = 5
	modal_tabs.add_theme_constant_override("h_separation",8)
	v.add_child(modal_tabs)
	for spec in [["incidents","Обращения"],["violations","Нарушения"],["assessment","Оценки"],["events","Журнал"],["archive","Архив"]]:
		var b := _button("Tab"+spec[0],spec[1],modal_tabs,_select_section.bind(spec[0]))
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		section_buttons[spec[0]] = b
	modal_scroll = ScrollContainer.new()
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	modal_scroll.follow_focus = true
	v.add_child(modal_scroll)
	var copy := VBoxContainer.new()
	_named(copy,"RecordCopy",modal_scroll)
	copy.size_flags_horizontal = SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation",20)
	_label("RecordTitle","",copy,29,true)
	_label("RecordDetail","",copy,24)
	var meta := _label("RecordMeta","",copy,18)
	meta.add_theme_color_override("font_color",Color("61685c"))
	var id_row := VBoxContainer.new()
	_named(id_row,"IdRow",v)
	var input := LineEdit.new()
	_named(input,"ReportId",id_row)
	input.theme = preload("res://theme/train_theme.tres")
	input.placeholder_text = "ID сохранённого рейса"
	input.max_length = 32
	input.custom_minimum_size.y = 44
	input.text_submitted.connect(_on_report)
	_button("OpenId","ОТКРЫТЬ ПО ID",id_row,_on_open_id)
	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation",12)
	v.add_child(pager)
	_button("Previous","‹",pager,_move_record.bind(-1)).custom_minimum_size.x = 52
	var count := _label("PageLabel","",pager,20)
	count.size_flags_horizontal = SIZE_EXPAND_FILL
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button("Next","›",pager,_move_record.bind(1)).custom_minimum_size.x = 52
	_button("Evidence","РАЗБОР РЕШЕНИЯ",v,_open_record,"primary")
	var status := _label("Status","",copy,18)
	status.hide()
	_button("Refresh","ОБНОВИТЬ ОТЧЁТ",v,func(): refresh_requested.emit()).hide()
	modal.hide()
	modal_panel.minimum_size_changed.connect(_fit_modal.call_deferred)

func _fit_modal() -> void:
	var inset := 12.0 if size.x < 720 else 36.0
	var dimensions := Vector2(minf(1080,size.x-inset*2),minf(680,size.y-inset*2))
	_rect(modal_panel,Rect2((size-dimensions)*0.5,dimensions))

func _adapt_layout() -> void:
	if not is_node_ready(): return
	_compact = size.x < 720
	if _compact:
		stage.size = Vector2(720,1550)
		var mobile := {"Header":Rect2(0,0,720,134),"LoyaltyPanel":Rect2(20,335,333,220),"SafetyPanel":Rect2(367,335,333,220),"Stats":Rect2(20,571,680,116),"CrewPanel":Rect2(20,703,680,182),"DecisionsPanel":Rect2(20,901,680,182),"Training":Rect2(20,1099,680,106),"Seal":Rect2(20,1221,680,78),"Footer":Rect2(0,1315,720,235)}
		for group in groups: _rect(group,mobile[group.name])
		_rect(hero,Rect2(0,134,720,190))
		hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		%Title.add_theme_font_size_override("font_size",62)
		%Title.size.x = 650
		%Subtitle.size.x = 650
		%Subtitle.add_theme_font_size_override("font_size",27)
		for id in ["Loyalty","Safety"]:
			get_node("%"+id).position.x = 150
			get_node("%"+id).size.x = 175
			get_node("%"+id+"Bar").size.x = 271
			get_node("%"+id+"Caption").add_theme_font_size_override("font_size",29)
			get_node("%"+id+"Caption").size.x = 271
			get_node("%"+id+"Note").size.x = 271
			get_node("%"+id+"Note").add_theme_font_size_override("font_size",19)
		_adapt_stats(true)
		%Recommendation.size = Vector2(530,88)
		%Recommendation.position.y = 5
		%Recommendation.add_theme_font_size_override("font_size",25)
		%SealText.size.x = 540
		%Actions.vertical = true
		%Actions.add_theme_constant_override("separation",8)
		_rect(%Actions,Rect2(20,10,680,210))
		for b in [%Debrief,%Replay,%Profile]: b.custom_minimum_size = Vector2(0,60)
		%Archive.hide()
	else:
		stage.size = Vector2(1672,941)
		for group in groups: _rect(group,positions[group.name])
		_rect(hero,Rect2(854,0,818,393))
		hero.stretch_mode = TextureRect.STRETCH_SCALE
		%Title.add_theme_font_size_override("font_size",72)
		%Title.size.x = 825
		%Subtitle.size.x = 795
		%Subtitle.add_theme_font_size_override("font_size",29)
		for id in ["Loyalty","Safety"]:
			get_node("%"+id).position.x = 178
			get_node("%"+id).size.x = 193
			get_node("%"+id+"Bar").size.x = 333 if id == "Loyalty" else 320
			get_node("%"+id+"Caption").add_theme_font_size_override("font_size",33)
			get_node("%"+id+"Caption").size.x = 330
			get_node("%"+id+"Note").size.x = 333 if id == "Loyalty" else 320
			get_node("%"+id+"Note").add_theme_font_size_override("font_size",21)
		_adapt_stats(false)
		%Recommendation.size = Vector2(851,58)
		%Recommendation.position.y = 10
		%Recommendation.add_theme_font_size_override("font_size",26)
		%SealText.size.x = 195
		%Actions.vertical = false
		%Actions.add_theme_constant_override("separation",28)
		_rect(%Actions,Rect2(54,18,1342,82))
		%Debrief.custom_minimum_size = Vector2(435,52)
		%Replay.custom_minimum_size = Vector2(505,52)
		%Profile.custom_minimum_size = Vector2(346,52)
		%Archive.show()
	# Let the paper and footer follow actual wrapped text height.
	var training_h := maxf(106 if _compact else 78,_wrapped_height(%Recommendation)+28)
	%Training.size.y = training_h
	%Recommendation.size.y = training_h-20
	var seal_h := maxf(78,_wrapped_height(%SealText)+28)
	%Seal.size.y = seal_h
	%SealText.position.y = 10
	%SealText.size.y = seal_h-20
	# Override the initial deferred rectangle too, after measuring wrapped copy.
	%Training.set_deferred("size",%Training.size)
	%Seal.set_deferred("size",%Seal.size)
	if _compact:
		%Seal.position.y = %Training.position.y+training_h+16
		%Footer.position.y = %Seal.position.y+seal_h+16
	else:
		%Footer.position.y = maxf(%Training.position.y+training_h,%Seal.position.y+seal_h)+16
	stage.size.y = %Footer.position.y+%Footer.size.y
	var factor := size.x/stage.size.x if _compact else minf(size.x/1672.0,size.y/stage.size.y)
	stage.scale = Vector2.ONE*factor
	stage.position = Vector2(maxf(0,(size.x-stage.size.x*factor)/2),0 if _compact else maxf(0,(size.y-stage.size.y*factor)/2))
	canvas.custom_minimum_size.y = stage.size.y*factor
	_fit_modal()
	modal_tabs.columns = 2 if size.x < 720 else 5
	%ModalTitle.add_theme_font_size_override("font_size",21 if size.x < 720 else 30)
	%RecordTitle.add_theme_font_size_override("font_size",23 if size.x < 720 else 29)
	%RecordDetail.add_theme_font_size_override("font_size",20 if size.x < 720 else 24)

func _wrapped_height(label: Label) -> float:
	return label.get_theme_font("font").get_multiline_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,label.size.x,label.get_theme_font_size("font_size")).y

func _adapt_stats(compact: bool) -> void:
	for i in 3:
		var column := get_node("%StatColumn"+str(i))
		column.add_theme_constant_override("separation",12 if compact else 46)
		var icon := get_node("%StatIcon"+str(i))
		icon.custom_minimum_size = Vector2(42,42) if compact else Vector2(76,76)
		icon.visible = not compact
	for id in ["Solved","Missed","Points"]:
		get_node("%"+id+"Caption").add_theme_font_size_override("font_size",25)
		get_node("%"+id).add_theme_font_size_override("font_size",44 if compact else 50)

func present(value: Dictionary) -> void:
	report = value
	%Title.text = "РЕЙС ЗАВЕРШЁН"
	%Subtitle.text = "Москва — Санкт-Петербург · Рейс 01"
	%Subtitle.tooltip_text = "Сохранён: "+Progress.saved_date(value.get("completed_at"))
	var scales: Dictionary = value.get("scales",{})
	metric_targets = {"Loyalty":scales.get("overall_loyalty",scales.get("loyalty",{}).get("luggage-owner")),"Safety":scales.get("safety")}
	var incidents: Array = value.get("incidents",[])
	var solved := 0
	var missed := 0
	var arrivals: Array[float] = []
	var urgent := 0
	var urgent_arrived := 0
	for incident in incidents:
		var state := Crew.status_key(incident)
		if state == "resolved": solved += 1
		if state == "missed": missed += 1
		if incident.get("arrived_at") != null and incident.get("appeared_at") != null:
			arrivals.append(maxf(0,float(incident.arrived_at)-float(incident.appeared_at)))
		if incident.get("priority") == "high":
			urgent += 1
			if incident.get("arrived_at") != null: urgent_arrived += 1
	if value.has("resolved_incident_ids"): solved = value.resolved_incident_ids.size()
	if value.has("missed_incident_ids"): missed = value.missed_incident_ids.size()
	%Solved.text = "%s из %s" % [solved,incidents.size()] if not incidents.is_empty() else "—"
	%Missed.text = str(missed) if not incidents.is_empty() or value.has("missed_incident_ids") else "—"
	var points: Dictionary = value.get("points",{})
	%Points.text = ("+"+Text.metric(points.awarded)) if points.has("awarded") else "—"
	%Points.tooltip_text = Progress.report_points(value)
	%PointsCaption.text = "Очки"
	%PointsCaption.tooltip_text = "Очки, добавленные в прогресс профиля"
	%SafetyNote.text = "Критических нарушений: %s" % value.get("critical_marks",[]).size()
	%LoyaltyNote.text = "По итогам обращений"
	var average := 0.0
	for t in arrivals: average += t
	%CrewLine0.text = "Среднее прибытие: %s с" % Text.metric(average/arrivals.size()) if not arrivals.is_empty() else "Время прибытия не записано"
	%CrewLine1.text = ("Все срочные обращения приняты" if urgent == urgent_arrived else "Принято срочных: %s из %s" % [urgent_arrived,urgent]) if urgent > 0 else "Срочных обращений не было"
	_set_status_icon(%CrewIcon0,not arrivals.is_empty())
	_set_status_icon(%CrewIcon1,urgent == urgent_arrived)
	var aisle: Variant = value.get("facts",{}).get("luggage-1",{}).get("aisle_clear",value.get("facts",{}).get("aisle_clear"))
	%DecisionsLine0.text = "Проход освобождён" if aisle == true else ("Проход остался занят" if aisle == false else "Результаты — в разборе решений")
	_set_status_icon(%DecisionsIcon0,aisle == true)
	var unchecked := 0
	var checked := 0
	for entry in value.get("history",[]):
		for evidence in entry.get("competency_evidence",[]):
			if evidence.get("criterion") == "check_before_promise":
				if evidence.get("result") == "met": checked += 1
				elif evidence.get("result") in ["not_met","missed","failed"]: unchecked += 1
	%DecisionsLine1.text = "Без проверки условий: %s" % unchecked if unchecked > 0 else ("Условия проверены до обещания" if checked > 0 else "Проверьте объяснения действий")
	_set_status_icon(%DecisionsIcon1,unchecked == 0 and checked > 0)
	%Recommendation.text = "Следующая тренировка: "+str(value.get("recommendation","разберите решения этого рейса."))
	%Recommendation.tooltip_text = %Recommendation.text
	var safe: bool = value.has("critical_marks") and value.critical_marks.is_empty() and metric_targets.Safety != null and float(metric_targets.Safety) >= 80 and missed == 0
	%SealText.text = "БЕЗОПАСНЫЙ РЕЙС" if safe else "ЕСТЬ ЧТО УЛУЧШИТЬ"
	%Debrief.disabled = value.get("history",[]).is_empty()
	%Debrief.refresh()
	%Status.hide()
	%Refresh.hide()
	%IdRow.hide()
	_close_modal(true)
	_apply_metrics(1.0)
	if is_visible_in_tree(): _open()

func _set_status_icon(icon: Control, positive: bool) -> void:
	icon.symbol = "check" if positive else "warning"
	icon.color = Color("58745c") if positive else Color("a27a35")
	icon.queue_redraw()
func _apply_metrics(progress: float) -> void:
	for id in metric_targets:
		var value: Variant = metric_targets[id]
		get_node("%"+id).text = Text.metric(value) if progress >= 1.0 else str(roundi(float(value)*progress)) if value != null else "—"
		get_node("%"+id+"Bar").value = float(value)*progress if value != null else 0
		get_node("%"+id).add_theme_font_size_override("font_size",76 if value != null and not is_equal_approx(float(value),roundf(float(value))) else 89)
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
	_apply_metrics(1.0)
	if reduced_motion: return
	entry_motion = create_tween().set_ignore_time_scale(true).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in groups.size():
		var g := groups[i]
		g.modulate.a = 0
		g.pivot_offset = g.size*0.5
		g.scale = Vector2.ONE*0.988
		var delay := i*0.055
		entry_motion.tween_property(g,"modulate:a",1.0,0.38).set_delay(delay)
		entry_motion.tween_property(g,"scale",Vector2.ONE,0.48).set_delay(delay)
	_apply_metrics(0.0)
	entry_motion.tween_method(_apply_metrics,0.0,1.0,0.85).set_delay(0.16)

func _select_section(value: String) -> void:
	section = value
	record_page = 0
	_render_section()
	var was_open := modal.visible
	if modal_motion and modal_motion.is_valid(): modal_motion.kill()
	if not was_open:
		previous_focus = get_viewport().gui_get_focus_owner()
		modal.show()
		modal.modulate.a = 0 if not reduced_motion else 1
		%CloseDetails.grab_focus()
	if reduced_motion:
		modal.modulate.a = 1
	elif modal.modulate.a < 1:
		modal_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		modal_motion.tween_property(modal,"modulate:a",1.0,0.24)
	for key in section_buttons:
		section_buttons[key].kind = "primary" if key == section else "secondary"
		section_buttons[key].queue_redraw()
	%IdRow.hide()
	_fit_modal.call_deferred()
	_wire_modal_focus()
func _wire_modal_focus() -> void:
	var items: Array[Control] = []
	for node in modal.find_children("*","Control",true,false):
		if node.focus_mode == FOCUS_ALL and node.is_visible_in_tree() and not (node is BaseButton and node.disabled): items.append(node)
	for i in items.size():
		items[i].focus_next = items[(i+1)%items.size()].get_path()
		items[i].focus_previous = items[(i-1+items.size())%items.size()].get_path()
		items[i].focus_neighbor_top = items[i].focus_previous
		items[i].focus_neighbor_bottom = items[i].focus_next
func _close_modal(immediate := false) -> void:
	if not is_instance_valid(modal): return
	if modal_motion and modal_motion.is_valid(): modal_motion.kill()
	if immediate or reduced_motion:
		modal.hide()
		return
	modal_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	modal_motion.tween_property(modal,"modulate:a",0.0,0.18)
	modal_motion.tween_callback(func():
		modal.hide()
		if is_instance_valid(previous_focus): previous_focus.grab_focus())
func _move_record(direction: int) -> void:
	var next := clampi(record_page+direction,0,maxi(0,records.size()-1))
	if next == record_page: return
	record_page = next
	_render_record()
func _render_record() -> void:
	if record_motion and record_motion.is_valid(): record_motion.kill()
	var item: Dictionary = records[record_page] if not records.is_empty() else {}
	%RecordTitle.text = str(item.get("title","В этом разделе пока нет записей"))
	%RecordDetail.text = str(item.get("detail",""))
	%RecordMeta.text = str(item.get("footnote",""))
	%RecordMeta.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	%Evidence.visible = item.has("target")
	%Evidence.text = str(item.get("action","Разбор решения")).to_upper()
	%Previous.disabled = record_page <= 0
	%Next.disabled = record_page >= records.size()-1
	%Previous.refresh()
	%Next.refresh()
	%PageLabel.text = "%s из %s" % [record_page+1,records.size()] if not records.is_empty() else "Нет записей"
	modal_scroll.scroll_vertical = 0
	_fit_modal.call_deferred()
	%RecordCopy.modulate.a = 1 if reduced_motion else 0.15
	if not reduced_motion:
		record_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		record_motion.tween_property(%RecordCopy,"modulate:a",1.0,0.22)
	_wire_modal_focus()
func _open_record() -> void:
	if records.is_empty(): return
	var record: Dictionary = records[record_page]
	if record.get("target_kind") == "journal":
		_select_section("events")
		for i in records.size():
			if (records[i].has("event_id") and records[i].event_id in record.get("event_ids",[])) or (records[i].has("history_index") and records[i].history_index in record.get("history_indices",[])):
				record_page = i
				_render_record()
				return
		return
	var target := str(records[record_page].get("target",""))
	_close_modal(true)
	if section == "archive": _on_report(target)
	else: _on_evidence(target)
func present_archive(values: Array) -> void:
	saved_reports = values.duplicate(true)
	if section == "archive" and modal.visible: _render_section()
func set_status(message: String, failed_state := false, loading_state := false) -> void:
	%Status.text = message
	%Status.show()
	%Refresh.visible = failed_state
	%Refresh.disabled = loading_state
func loading() -> void:
	_select_section("archive")
	records = [{"title":"Загружаем отчёт…","detail":"Сохранённые итоги появятся через несколько секунд."}]
	_render_record()
	set_status("Загрузка…",false,true)
func failed(message: String) -> void:
	_select_section("archive")
	set_status(message,true)
func set_locked(value: bool) -> void:
	_locked = value
	%Replay.disabled = value
	%Replay.refresh()
func _on_debrief() -> void: debrief_requested.emit("")
func _on_evidence(request_id: String) -> void: debrief_requested.emit(request_id)
func _on_report(id: String) -> void:
	if not id.strip_edges().is_empty(): report_requested.emit(id.strip_edges())
func _on_open_id() -> void: _on_report(%ReportId.text)
func _on_replay() -> void:
	if not _locked: replay_requested.emit()
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	if modal.visible:
		if event.keycode == KEY_ESCAPE: _close_modal()
		elif event.keycode == KEY_LEFT and not %ReportId.has_focus(): _move_record(-1)
		elif event.keycode == KEY_RIGHT and not %ReportId.has_focus(): _move_record(1)
		else: return
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		replay_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_TAB and get_viewport().gui_get_focus_owner() == null:
		%Debrief.grab_focus()
		get_viewport().set_input_as_handled()

func _render_section() -> void:
	records = []
	var empty_text := "Для этого рейса записи раздела не сохранены."
	match section:
		"incidents": records = Progress.incident_records(report)
		"violations":
			records = Progress.violation_records(report)
			empty_text = "Критических нарушений нет — по сохранённому отчёту."
		"assessment":
			records = Progress.assessment_records(report)
			empty_text = "Оценки компетенций для этого рейса не сохранены. Можно открыть разбор отдельных действий."
		"events": records = Progress.journal_records(report)
		"training": records.append({"title":"Следующая тренировка","detail":Progress.prose(report.get("recommendation")),"footnote":Progress.prose(report.get("summary"),"")})
		"archive":
			records = Progress.archive_records(saved_reports,report)
			empty_text = "Завершённые рейсы появятся здесь после сохранения результата."
	if records.is_empty(): records.append({"title":"Критических нарушений нет" if section == "violations" else "Нет записей","detail":empty_text})
	record_page = clampi(record_page,0,maxi(0,records.size()-1))
	_render_record()
