extends "res://scripts/progress_screen.gd"
signal debrief_requested(request_id: String)
signal report_requested(trip_id: String)
const Text = preload("res://scripts/server_text.gd")
const Crew = preload("res://scripts/crew_state.gd")
const Progress = preload("res://scripts/progress_data.gd")
var report: Dictionary = {}
var section := "incidents"

func _ready() -> void:
	resized.connect(_adapt_layout)
	_adapt_layout()
	%Body.visible = false

func _adapt_layout() -> void:
	%Metrics.columns = 2 if size.x >= 620 else 1
	%Sections.columns = 4 if size.x >= 760 else 2

func present(value: Dictionary) -> void:
	report = value
	%Body.visible = true
	%Subtitle.text = "Сохранённый отчёт · %s\nРейс %s" % [str(value.get("completed_at", "")), value.trip_id]
	%Subtitle.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	%Summary.text = value.summary
	var loyalty: Variant = value.scales.get("overall_loyalty", value.scales.loyalty.get("luggage-owner"))
	%Loyalty.text = "Лояльность · " + Text.metric(loyalty)
	%LoyaltyBar.visible = loyalty != null
	%LoyaltyBar.value = float(loyalty) if loyalty != null else 0.0
	%Safety.text = "Безопасность · " + Text.metric(value.scales.safety)
	%SafetyBar.value = value.scales.safety
	%Points.text = Progress.report_points(value)
	%Recommendation.text = "Следующая тренировка\n" + value.recommendation
	set_status("Получено с сервера · версия %s · учебные формулировки: %s" % [value.scenario_version, "черновик" if value.get("text_status") == "draft" else str(value.get("text_status", "не указано"))])
	_render_section()
	scroll_vertical = 0

func loading() -> void:
	%Body.visible = false
	set_status("Загружаем сохранённый отчёт…", false, true)

func failed(message: String) -> void:
	%Body.visible = false
	set_status(message, true)

func _select_section(value: String) -> void:
	section = value
	_render_section()

func _render_section() -> void:
	var records: Array = []
	var empty_text := "Сервер не передал записи этого раздела."
	match section:
		"incidents":
			for incident in report.get("incidents", []):
				var record := {"title": incident.text + " · " + Crew.status_text(incident), "detail": str(incident.get("summary", incident.get("success_explanation", ""))) + "\n" + str(incident.get("recommendation", "")), "footnote": "Обращение: " + incident.id}
				# A service timeout must display its timeout explanation, not its success text.
				if Crew.status_key(incident) == "missed":
					record.detail = str(incident.get("summary", incident.get("timeout_explanation", ""))) + "\n" + str(incident.get("recommendation", ""))
				for entry in report.history:
					if entry.get("incident_id") == incident.id:
						record.target = entry.request_id
						record.action = "Решение из журнала"
						break
				records.append(record)
		"violations":
			empty_text = "Критических нарушений нет — по сохранённому отчёту сервера."
			for mark in report.critical_marks:
				var record := {"title": Progress.violation(str(mark)), "detail": "Критическая отметка сохранённой попытки.", "footnote": str(mark)}
				for entry in report.history:
					if mark in entry.get("effects", {}).get("critical_marks", []):
						record.detail = entry.explanation
						record.target = entry.request_id
						record.action = "Показать действие"
						break
				records.append(record)
		"assessment":
			records = Progress.assessment_records(report)
			empty_text = "Сервер Б4 не передал итоговые оценки компетенций. Для них требуется Б5."
		"events":
			for event in report.get("events", []):
				records.append({"title": "#%s · %s" % [event.get("id", "—"), Progress.event_name(event.get("type", ""))], "detail": "Время рейса: %s с\nОбращение: %s\nСотрудник: %s" % [Text.metric(event.get("simulation_time")), event.get("incident_id", "—"), event.get("staff_id", "—")], "footnote": JSON.stringify(event)})
	%Records.present(records, empty_text)

func _on_debrief() -> void:
	debrief_requested.emit("")

func _on_evidence(request_id: String) -> void:
	debrief_requested.emit(request_id)

func present_archive(values: Array) -> void:
	var records: Array = []
	for entry in values:
		records.append({"title": "Сохранённый рейс", "detail": entry.completed_at, "footnote": entry.trip_id, "target": entry.trip_id, "action": "Открыть отчёт"})
	%SavedReports.present(records, "На этом устройстве ещё нет ссылок на завершённые рейсы.")

func _on_report(id: String) -> void:
	report_requested.emit(id.strip_edges())

func _on_open_id() -> void:
	_on_report(%ReportId.text)
