extends ScrollContainer
signal request_selected(request_id: String)
signal back_requested
const Text = preload("res://scripts/server_text.gd")
var requests: Array = []
var page := 0
const PAGE_SIZE := 3
var locked := false
@onready var rows: Array = [%Row1, %Row2, %Row3]
@onready var carriage = $Margin/Content/MainGrid/CarriagePanel/Carriage

func _ready() -> void:
	resized.connect(_adapt_layout)
	_adapt_layout()

func _adapt_layout() -> void:
	%MainGrid.columns = 2 if size.x >= 900 else 1
	%CrewGrid.columns = 3 if size.x >= 760 else 1
	%Metrics.columns = 3 if size.x >= 620 else 1

func show_trip(state: Dictionary) -> void:
	requests = state.incidents
	page = 0
	%Confirmation.text = "Попытка %s · версия %s\n%s · %s" % [state.trip_id.left(8), state.state_version, Text.condition(state.conditions), Text.facts(state.facts)]
	%CarriageTitle.text = state.carriages[0].name
	%TimeText.text = "Без ограничения времени" if state.get("remaining_time") == null else "Осталось: %s" % state.remaining_time
	var loyalty: Variant = state.scales.get("overall_loyalty")
	if loyalty == null:
		loyalty = state.scales.loyalty.get("luggage-owner", 0)
	%LoyaltyText.text = "Лояльность пассажира: %s" % loyalty
	%LoyaltyValue.value = float(loyalty)
	%SafetyText.text = "Безопасность: %s" % state.scales.safety
	%SafetyValue.value = float(state.scales.safety)
	%CrewGrid.visible = false
	%CrewTitle.visible = false
	%StaffDetail.text = "Первый сценарий доступен без назначения проводника."
	carriage.bind_incidents(requests)
	_render_page()

func set_locked(value: bool) -> void:
	locked = value
	for row in rows:
		row.disabled = locked
	carriage.set_locked(locked)

func _render_page() -> void:
	var pages := maxi(1, ceili(float(requests.size()) / PAGE_SIZE))
	page = clampi(page, 0, pages - 1)
	for i in rows.size():
		var index := page * PAGE_SIZE + i
		rows[i].visible = index < requests.size()
		if index < requests.size():
			rows[i].bind_request(requests[index])
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

func _on_request_selected(request_id: String) -> void:
	if not locked:
		request_selected.emit(request_id)

func _on_back() -> void:
	back_requested.emit()

func _on_staff_selected(_staff_id: String) -> void:
	pass
