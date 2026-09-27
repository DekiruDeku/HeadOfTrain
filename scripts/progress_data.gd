extends RefCounted
## Presentation of server-owned B5 scores and evidence.
const Text = preload("res://scripts/server_text.gd")
const COMPETENCIES := {"communication": "Коммуникация", "safety": "Безопасность", "prioritization": "Приоритизация"}

static func report_points(report: Dictionary) -> String:
	var value: Variant = report.get("points")
	if not value is Dictionary:
		return "Очки · сервер пока не передал оценку Б5"
	return "Очки за попытку: %s · В прогресс: +%s\nПовтор учитывает только улучшение личного рекорда." % [Text.metric(value.get("earned")), Text.metric(value.get("awarded"))]

static func assessment_records(report: Dictionary) -> Array:
	var records: Array = []
	for item in report.get("competencies", []):
		records.append({"title": item.name, "detail": "Оценка: %s / %s" % [Text.metric(item.points), Text.metric(item.max_points)], "footnote": "Оценка сохранённой попытки"})
		for evidence in item.evidence:
			records.append({"title": "Основание · " + item.name, "detail": evidence.reason, "footnote": "Обращение: " + evidence.incident_id})
			for index in evidence.history_indices:
				var entry: Dictionary = report.history[int(index)]
				records.append({"title": "Действие · " + item.name, "detail": entry.explanation, "footnote": entry.request_id, "target": entry.request_id, "action": "Проверить по журналу"})
			for id in evidence.event_ids:
				for event in report.get("events", []):
					if event.get("id") == id:
						records.append({"title": "Событие #%s · %s" % [id, event_name(event.get("type", ""))], "detail": JSON.stringify(event), "footnote": evidence.reason})
	for item in report.get("scenario_scores", []):
		records.append({"title": "Результат · " + item.incident_id, "detail": "%s / %s очков · В прогресс: +%s" % [Text.metric(item.points), Text.metric(item.max_points), Text.metric(item.awarded)], "footnote": "Предыдущий рекорд: %s · %s" % [Text.metric(item.previous_best), item.scenario_version]})
	# B4 already supplies per-action evidence. Show all of it without deriving a score.
	for entry in report.get("history", []):
		for evidence in entry.get("competency_evidence", []):
			records.append({"title": "Основание · " + str(COMPETENCIES.get(evidence.get("competency"), evidence.get("competency", ""))), "detail": str(evidence.get("reason", entry.explanation)), "footnote": JSON.stringify(evidence), "target": entry.request_id, "action": "Проверить по журналу"})
	return records

static func violation(code: String) -> String:
	return {"aisle_left_blocked": "Проход оставлен заблокированным", "unsafe_placement": "Небезопасное размещение багажа"}.get(code, "Критическое нарушение · " + code)

static func event_name(code: String) -> String:
	return {"incident_appeared": "Поступило обращение", "assignment": "Назначен проводник", "arrival": "Проводник прибыл", "dialog_open": "Открыт диалог", "dialog_close": "Закрыт диалог", "trip_completed": "Рейс завершён", "service_completed": "Обслуживание завершено"}.get(code, code)
