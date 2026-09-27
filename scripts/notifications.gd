extends "res://scripts/progress_screen.gd"
signal list_requested(page: int)
var requested_page := 1

func _ready() -> void:
	%Records.page_requested.connect(_on_page)
	%Records.present([], "Уведомления ещё не загружены.")

func loading() -> void:
	%Records.set_loading()
	%FutureCarriage.present(null)
	set_status("Загружаем уведомления…", false, true)

func failed(message: String) -> void:
	requested_page = 1
	%Records.show_error("Уведомления не загружены. Повторите запрос.")
	%FutureCarriage.present(null)
	set_status(message, true)

func present(value: Dictionary) -> void:
	var records: Array = []
	for entry in value.notifications:
		records.append({"title": entry.title, "detail": entry.message, "footnote": entry.created_at})
	%Records.present_remote(records, int(value.page), int(value.total), "Новых событий пока нет. Уведомление появится после завершения рейса.")
	%FutureCarriage.present(false if value.total == 0 else null)
	for entry in value.notifications:
		if entry.carriage_id == "carriage-3" and entry.content_status == "future_content":
			%FutureCarriage.present(true)
	set_status("Уведомления получены с сервера.")

func _on_page(number: int) -> void:
	requested_page = number
	list_requested.emit(number)

func _on_refresh() -> void:
	list_requested.emit(requested_page)
