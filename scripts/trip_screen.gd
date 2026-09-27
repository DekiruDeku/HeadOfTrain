extends ScrollContainer
signal request_selected(request_id: String)
signal assignment_requested(incident_id: String, staff_id: String)
signal back_requested
const Text = preload("res://scripts/server_text.gd")
const Crew = preload("res://scripts/crew_state.gd")
const PAGE_SIZE := 3
var requests: Array = []
var state: Dictionary = {}
var selected_id := ""
var page := 0
var locked := false
var received_at := 0
var tick := 0.0
var focused_carriage := ""
@onready var rows: Array = [%Row1, %Row2, %Row3]
@onready var cards: Array = [%CrewGrid/Anna, %CrewGrid/Mikhail, %CrewGrid/Elena]
@onready var carriage = $Margin/Content/MainGrid/CarriagePanel/Carriage

func _ready() -> void:
	resized.connect(_adapt_layout)
	_adapt_layout()

func _adapt_layout() -> void:
	%MainGrid.columns = 1
	%CrewGrid.columns = 3 if size.x >= 760 else 1
	%Metrics.columns = 3 if size.x >= 620 else 1

func show_trip(value: Dictionary) -> void:
	if state.get("trip_id") != value.trip_id:
		selected_id = ""
		page = 0
		focused_carriage = ""
		carriage.focus_carriage("")
	state = value
	received_at = Time.get_ticks_msec()
	requests = state.incidents
	%Confirmation.text = "Попытка %s · версия %s\n%s · %s" % [state.trip_id.left(8), state.state_version, Text.condition(state.conditions), Text.facts(state.facts)]
	if state.has("fixture_label"):
		%Confirmation.text = "ФИКСТУРЫ А3 · не сохранённый результат\n" + str(state.fixture_label)
	%CarriageTitle.text = (state.carriages[0].name + "    /    " + state.carriages[1].name) if Crew.enabled(state) else state.carriages[0].name
	var loyalty: Variant = state.scales.get("overall_loyalty")
	%LoyaltyText.text = "Общая лояльность: " + Text.metric(loyalty)
	%LoyaltyValue.value = float(loyalty) if loyalty != null else 0.0
	%LoyaltyValue.visible = loyalty != null
	%SafetyText.text = "Безопасность: " + Text.metric(state.scales.safety)
	%SafetyValue.value = float(state.scales.safety)
	%CrewGrid.visible = Crew.enabled(state)
	%CrewTitle.visible = Crew.enabled(state)
	%CarriageTabs.visible = Crew.enabled(state)
	carriage.bind_state(state)
	_update_display()

func set_locked(value: bool) -> void:
	locked = value
	for row in rows:
		row.disabled = locked
	for card in cards:
		card.set_locked(locked)
	%OpenDialog.disabled = locked
	carriage.set_locked(locked)

func _process(delta: float) -> void:
	if state.is_empty():
		return
	var age := float(Time.get_ticks_msec() - received_at) / 1000.0
	var elapsed := 0.0 if state.get("paused", false) else minf(age, float(state.get("display_horizon", 2.0)))
	carriage.show_time(float(state.get("simulation_time", 0)) + elapsed)
	tick += delta
	if tick >= 0.15:
		tick = 0.0
		_update_display()

func _update_display() -> void:
	var age := float(Time.get_ticks_msec() - received_at) / 1000.0
	var elapsed := 0.0 if state.get("paused", false) else minf(age, float(state.get("display_horizon", 2.0)))
	var sim := float(state.get("simulation_time", 0)) + elapsed
	%TimeText.text = "Без ограничения времени" if state.get("remaining_time") == null else "До конца рейса: " + Crew.seconds(float(state.remaining_time) - elapsed)
	if state.get("paused", false):
		%TimeText.text += "\nПАУЗА · открыт диалог"
	if Crew.enabled(state) and age > 2.5:
		%TimeText.text += "\nОжидаем актуальное время сервера"
	_render_page(elapsed)
	var selected: Dictionary = {}
	for incident in requests:
		if incident.id == selected_id:
			selected = incident
	%OpenDialog.visible = not selected.is_empty() and selected.state == "resolving" and selected.type != "service" and Crew.enabled(state)
	if not Crew.enabled(state):
		%StaffDetail.text = "Сохранённая попытка первого сценария без бригады. Следующая тренировка начнётся с полного рейса."
	else:
		%StaffDetail.text = "Выберите обращение на схеме или в списке."
		if not selected.is_empty():
			%StaffDetail.text = selected.text + "\n" + Crew.priority_text(selected) + " · " + Crew.status_text(selected)
			if selected.state == "waiting":
				%StaffDetail.text += "\nВыберите свободного сотрудника. Время прибытия получено из API."
			elif selected.state == "en_route":
				%StaffDetail.text += "\nНазначение принято; срок реакции продолжается до прибытия."
			elif selected.state == "resolving" and selected.type == "service":
				%StaffDetail.text += "\nОбслуживание завершится автоматически по данным сервера."
			elif selected.state == "resolving":
				%StaffDetail.text += "\nСотрудник на месте. Откройте диалог, чтобы принять решение."
		var entry := Crew.latest_entry(state, selected_id)
		%SelectedOutcome.visible = not entry.is_empty()
		if not entry.is_empty():
			%SelectedOutcome.text = "Последнее подтверждённое действие\n" + entry.selected_text + "\n" + Text.effects(entry.effects) + "\n" + entry.explanation
		for card in cards:
			for member in state.staff:
				if Crew.visual_staff(member.id) == Crew.visual_staff(card.staff_id):
					card.bind_member(member, Crew.eta(state, member.id, selected_id), not selected.is_empty() and selected.state == "waiting", sim)
	_update_overview()

func _update_overview() -> void:
	var active := 0
	var missed := 0
	var resolved := 0
	var counts := {"carriage-1": 0, "carriage-2": 0}
	for incident in requests:
		if incident.state != "completed":
			active += 1
			counts[incident.carriage_id] += 1
		elif Crew.status_key(incident) == "missed":
			missed += 1
		elif Crew.status_key(incident) == "resolved":
			resolved += 1
	var free := 0
	for member in state.get("staff", []):
		if member.state == "free":
			free += 1
	%Overview.text = "Активных: %s · решено: %s · пропущено: %s · свободных сотрудников: %s" % [active, resolved, missed, free]
	if active > 1:
		%Overview.text += "\nНесколько обращений одновременно: сравните приоритет, срок реакции и время прибытия."
	%Carriage1.text = "Вагон 01 · %s" % counts["carriage-1"]
	%Carriage2.text = "Вагон 02 · %s" % counts["carriage-2"]
	%AllCarriages.button_pressed = focused_carriage.is_empty()
	%Carriage1.button_pressed = focused_carriage == "carriage-1"
	%Carriage2.button_pressed = focused_carriage == "carriage-2"
	%Overview.visible = Crew.enabled(state)

func _render_page(elapsed: float = 0.0) -> void:
	var pages := maxi(1, ceili(float(requests.size()) / PAGE_SIZE))
	page = clampi(page, 0, pages - 1)
	for i in rows.size():
		var index := page * PAGE_SIZE + i
		rows[i].visible = index < requests.size()
		if index < requests.size():
			rows[i].bind_request(requests[index], elapsed, requests[index].id == selected_id)
	%PageLabel.text = "%s / %s" % [page + 1, pages]
	%Previous.disabled = page == 0
	%Next.disabled = page == pages - 1
	%RequestCount.text = "Обращения · %s" % requests.size()

func _on_previous() -> void:
	page -= 1
	_render_page()

func _on_next() -> void:
	page += 1
	_render_page()

func _on_request_selected(id: String) -> void:
	if locked:
		return
	if not Crew.enabled(state):
		request_selected.emit(id)
		return
	selected_id = id
	for i in requests.size():
		if requests[i].id == id:
			page = i / PAGE_SIZE
			if not focused_carriage.is_empty():
				_on_carriage_selected(requests[i].carriage_id)
	_update_display()
	call_deferred("ensure_control_visible", %CrewGrid)

func _on_carriage_selected(id: String) -> void:
	focused_carriage = id
	carriage.focus_carriage(id)
	_update_overview()

func _on_open_dialog() -> void:
	if not locked:
		request_selected.emit(selected_id)

func _on_back() -> void:
	back_requested.emit()

func _on_staff_selected(staff_id: String) -> void:
	if not locked and not selected_id.is_empty():
		assignment_requested.emit(selected_id, staff_id)
