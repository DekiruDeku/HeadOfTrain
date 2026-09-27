extends "res://scripts/progress_screen.gd"
signal list_requested(scope: String, page: int)
const Text = preload("res://scripts/server_text.gd")
const SCOPES := {"crew": "Бригада", "depot": "Депо", "company": "Компания"}
var scope := "crew"
var requested_page := 1

func _ready() -> void:
	resized.connect(_adapt_layout)
	_adapt_layout()
	%Records.present([], "Выберите фильтр или обновите рейтинг.")

func _adapt_layout() -> void:
	%Filters.columns = 3 if size.x >= 560 else 1

func loading() -> void:
	%Records.set_loading()
	%OwnRank.text = "Ваше место · загружается"
	%ScopeLabel.text = SCOPES[scope]
	set_status("Загружаем рейтинг…", false, true)

func failed(message: String) -> void:
	requested_page = 1
	%Records.show_error("Рейтинг не загружен. Повторите запрос.")
	%OwnRank.text = "Ваше место · не подтверждено"
	set_status(message, true)

func present(value: Dictionary) -> void:
	var records: Array = []
	for entry in value.entries:
		records.append({"title": "#%s · %s%s" % [int(entry.rank), entry.display_name, " · Вы" if entry.is_self else ""], "detail": "Очки: %s" % Text.metric(entry.total_points), "footnote": "ДЕМО · демонстрационная запись" if entry.is_demo else "Результат сохранённых тренировок"})
	%ScopeLabel.text = SCOPES[scope] + " · " + value.scope_id
	%OwnRank.text = "Ваше место показано в строке «Вы» на соответствующей странице."
	for entry in value.entries:
		if entry.is_self:
			%OwnRank.text = "Ваше место: " + Text.metric(entry.rank)
	%Records.present_remote(records, int(value.page), int(value.total), "В выбранной группе пока нет результатов.")
	set_status("Рейтинг получен с сервера.")

func _on_scope(value: String) -> void:
	scope = value
	requested_page = 1
	list_requested.emit(scope, requested_page)

func _on_page(number: int) -> void:
	requested_page = number
	list_requested.emit(scope, requested_page)

func _on_refresh() -> void:
	list_requested.emit(scope, requested_page)
