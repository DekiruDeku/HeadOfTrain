extends VBoxContainer
## Three saved row instances. Local arrays are never truncated; remote pages
## must match the negotiated page_size and are validated by ProgressAPI.
signal activated(value: String)
signal page_requested(page: int)
const PAGE_SIZE := 3
var records: Array = []
var page := 1
var total := 0
var remote := false
var locked := false
@onready var rows: Array = [%Row1, %Row2, %Row3]

func present(values: Array, empty_text: String = "Записей пока нет.") -> void:
	records = values
	remote = false
	page = 1
	total = records.size()
	locked = false
	%Empty.text = empty_text
	_render()

func present_remote(values: Array, number: int, count: int, empty_text: String) -> void:
	records = values
	remote = true
	page = number
	total = count
	locked = false
	%Empty.text = empty_text
	_render()

func set_loading() -> void:
	locked = true
	for row in rows:
		row.visible = false
	%Empty.visible = true
	%Empty.text = "Загружаем записи…"
	%Previous.disabled = true
	%Next.disabled = true
	%PageLabel.text = "Загрузка…"

func show_error(detail: String) -> void:
	present([], detail)

func _render() -> void:
	var pages := maxi(1, ceili(float(total) / PAGE_SIZE))
	page = clampi(page, 1, pages)
	var offset := 0 if remote else (page - 1) * PAGE_SIZE
	for i in rows.size():
		rows[i].visible = offset + i < records.size()
		if rows[i].visible:
			rows[i].present(records[offset + i])
	%Empty.visible = records.is_empty()
	%PageLabel.text = "Страница %s / %s · Всего: %s" % [page, pages, total]
	%Previous.disabled = locked or page <= 1
	%Next.disabled = locked or page >= pages

func _move(direction: int) -> void:
	if locked:
		return
	var next_page := clampi(page + direction, 1, maxi(1, ceili(float(total) / PAGE_SIZE)))
	if next_page == page:
		return
	if remote:
		page_requested.emit(next_page)
	else:
		page = next_page
		_render()

func _on_previous() -> void:
	_move(-1)

func _on_next() -> void:
	_move(1)

func _on_activated(value: String) -> void:
	activated.emit(value)
