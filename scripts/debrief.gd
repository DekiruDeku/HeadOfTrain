extends ScrollContainer
signal back_requested
signal continue_requested
signal report_requested
const Text = preload("res://scripts/server_text.gd")
const Crew = preload("res://scripts/crew_state.gd")
var history: Array = []
var page := 0
var final_report := false
var saved_report: Dictionary = {}

func present_effect(entry: Dictionary, state: Dictionary) -> void:
	final_report = false
	%Back.text = "Вернуться к вагону"
	%TripId.visible = false
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

func present_report(report: Dictionary, trip: Dictionary = {}) -> void:
	final_report = true
	saved_report = report
	history = report.history
	page = 0
	%Title.text = "Рейс завершён · сохранённый разбор"
	%Summary.text = report.summary
	%Recommendation.visible = true
	%Recommendation.text = "Рекомендация\n" + report.recommendation
	%Facts.text = Text.facts(report.facts) + "\n" + Text.scales(report.scales)
	%Persistence.text = "Сохранённый разбор · версия %s\nСценарий %s · %s · учебные формулировки — черновик." % [report.state_version, report.scenario_id, report.scenario_version]
	%TripId.text = "trip_id: " + report.trip_id
	%TripId.visible = true
	%Continue.text = "К новой тренировке"
	%Back.text = "К отчёту"
	_render_page()
	scroll_vertical = 0

func _render_page() -> void:
	page = clampi(page, 0, maxi(0, history.size() - 1))
	%PageLabel.text = "Запись %s / %s" % [page + 1 if not history.is_empty() else 0, history.size()]
	%Previous.disabled = page == 0
	%Next.disabled = page >= history.size() - 1
	if history.is_empty():
		%Choice.text = "В истории нет решений."
		%Effect.text = ""
		%Explanation.text = ""
		%Evidence.text = "Сервер не сохранил действий в этой попытке."
		return
	var entry: Dictionary = history[page]
	%Choice.text = entry.selected_text
	%Effect.text = Text.effects(entry.effects)
	%Explanation.text = entry.explanation
	%Evidence.text = "Запись журнала: %s\nОбращение: %s · Действие: %s\n%s → %s\nВремя рейса: %s с · На решение: %s с\nИсточник: %s" % [entry.request_id, entry.get("incident_id", "—"), entry.get("action_id", "—"), entry.get("node_before", "—"), entry.get("node_after", "—"), Text.metric(entry.get("simulation_time")), Text.metric(entry.get("decision_time_seconds")), {"player": "выбор игрока", "service": "обслуживание", "timeout": "истечение времени"}.get(entry.get("source"), str(entry.get("source", "сервер")))]
	if final_report:
		%Recommendation.text = "Рекомендация\n" + saved_report.recommendation
		for incident in saved_report.get("incidents", []):
			if incident.id == entry.get("incident_id") and incident.get("recommendation") is String:
				%Recommendation.text = "Следующая тренировка\n" + incident.recommendation

func select_evidence(request_id: String) -> void:
	if request_id.is_empty():
		return
	for i in history.size():
		if history[i].request_id == request_id:
			page = i
			_render_page()
			return
	%Evidence.text = "Запись основания не найдена в этом отчёте: " + request_id

func set_locked(locked: bool) -> void:
	%Continue.disabled = locked

func _on_previous() -> void:
	page -= 1
	_render_page()

func _on_next() -> void:
	page += 1
	_render_page()

func _on_back() -> void:
	if final_report:
		report_requested.emit()
	else:
		back_requested.emit()

func _on_continue() -> void:
	continue_requested.emit()
