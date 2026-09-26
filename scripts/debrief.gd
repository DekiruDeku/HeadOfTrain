extends ScrollContainer
signal back_requested
signal continue_requested
const Text = preload("res://scripts/server_text.gd")
var history: Array = []
var page := 0

func present_effect(entry: Dictionary, state: Dictionary) -> void:
	history = [entry]
	page = 0
	%Title.text = "Последствие решения"
	%Summary.text = "Действие подтверждено и сохранено сервером."
	%Recommendation.visible = false
	%Facts.text = Text.facts(state.facts) + "\n" + Text.scales(state.scales)
	%Persistence.text = "Попытка продолжается. Можно закрыть страницу и вернуться к ней позже."
	%Continue.text = "Продолжить диалог"
	_render_page()
	scroll_vertical = 0

func present_report(report: Dictionary) -> void:
	history = report.history
	page = 0
	%Title.text = "Разбор · Чемодан в проходе"
	%Summary.text = report.summary
	%Recommendation.visible = true
	%Recommendation.text = "Рекомендация\n" + report.recommendation
	%Facts.text = Text.facts(report.facts) + "\n" + Text.scales(report.scales)
	if not report.critical_marks.is_empty():
		%Facts.text += "\nКритические отметки: " + ", ".join(report.critical_marks)
	%Persistence.text = "Сохранённый разбор · версия %s\nСценарий %s · %s · учебные формулировки — черновик." % [report.state_version, report.scenario_id, report.scenario_version]
	%Continue.text = "К новой тренировке"
	_render_page()
	scroll_vertical = 0

func _render_page() -> void:
	page = clampi(page, 0, maxi(0, history.size() - 1))
	%PageLabel.text = "Решение %s / %s" % [page + 1, history.size()]
	%Previous.disabled = page == 0
	%Next.disabled = page >= history.size() - 1
	if history.is_empty():
		%Choice.text = "В истории нет решений."
		%Effect.text = ""
		%Explanation.text = ""
		return
	var entry: Dictionary = history[page]
	%Choice.text = entry.selected_text
	%Effect.text = Text.effects(entry.effects)
	%Explanation.text = entry.explanation

func set_locked(locked: bool) -> void:
	%Continue.disabled = locked

func _on_previous() -> void:
	page -= 1
	_render_page()

func _on_next() -> void:
	page += 1
	_render_page()

func _on_back() -> void:
	back_requested.emit()

func _on_continue() -> void:
	continue_requested.emit()
