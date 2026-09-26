extends ScrollContainer

signal request_selected(request_id: String)
signal back_requested

var requests: Array = []
var page := 0
const PAGE_SIZE := 3
@onready var rows: Array = [%Row1, %Row2, %Row3]

func _ready() -> void:
	resized.connect(_adapt_layout)
	_adapt_layout()

func _adapt_layout() -> void:
	%MainGrid.columns = 2 if size.x >= 900 else 1
	%CrewGrid.columns = 3 if size.x >= 760 else 1
	%Metrics.columns = 3 if size.x >= 620 else 1

func show_trip(data: Array, confirmation: String) -> void:
	requests = data
	page = 0
	%Confirmation.text = confirmation
	%StaffDetail.text = "Три сотрудника · имена и состояния вымышлены."
	_render_page()

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
	request_selected.emit(request_id)

func _on_back() -> void:
	back_requested.emit()

func _on_staff_selected(staff_id: String) -> void:
	var descriptions := {
		"anna": "Анна · свободна · вагон 01. Демо-карточка сотрудника; назначение появится на следующем этапе.",
		"mikhail": "Михаил · в пути · вагон 01. Демо-состояние, перемещение пока не моделируется.",
		"elena": "Елена · обслуживает · вагон 01. Демо-состояние, время обслуживания пока не отсчитывается."
	}
	%StaffDetail.text = descriptions[staff_id]
