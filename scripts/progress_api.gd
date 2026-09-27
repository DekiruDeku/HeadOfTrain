extends Node
## Read-only API transport, independent of the active-trip command queue.
## Server B5 contract: docs/api/b5/contract.md.
signal loading(kind: String)
signal received(kind: String, value: Dictionary)
signal failed(kind: String, message: String)
const PAGE_SIZE := 3
var requests: Dictionary = {}
@onready var session = get_parent().get_node("SessionAPI")
@onready var channels := {"profile": $ProfileRequest, "leaderboard": $LeaderboardRequest, "notifications": $NotificationsRequest, "archive": $ReportRequest}

func profile() -> void:
	_send("profile", "/api/profile")

func leaderboard(scope: String, page: int) -> void:
	if scope not in ["crew", "depot", "company"] or page < 1:
		return
	_send("leaderboard", "/api/leaderboard?scope=%s&page=%s&page_size=%s" % [scope, page, PAGE_SIZE], {"scope": scope, "page": page})

func notifications(page: int = 1) -> void:
	_send("notifications", "/api/notifications?page=%s&page_size=%s" % [page, PAGE_SIZE], {"page": page})

func archived_report(id: String) -> void:
	if id.length() != 32 or not id.is_valid_hex_number():
		failed.emit("archive", "ID рейса должен содержать 32 шестнадцатеричных символа.")
		return
	_send("archive", "/api/trips/%s/report" % id, {"trip_id": id})

func _send(kind: String, path: String, parameters: Dictionary = {}) -> void:
	if session.player_id.is_empty() or not session.storage_ok:
		failed.emit(kind, "Идентификатор игрока ещё не восстановлен. Восстановите связь и повторите загрузку.")
		return
	var channel: HTTPRequest = channels[kind]
	channel.cancel_request()
	requests[kind] = parameters
	loading.emit(kind)
	var err := channel.request(session._origin() + path, ["X-Demo-Player: " + session.player_id])
	if err != OK:
		failed.emit(kind, "Не удалось отправить запрос. Повторите загрузку.")

func _on_response(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray, kind: String) -> void:
	if not requests.has(kind):
		return
	var parameters: Dictionary = requests[kind]
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code == 0 or code >= 500:
		failed.emit(kind, "Не удалось получить данные сервера. Проверьте связь и повторите загрузку.")
		return
	if code == 404 and kind != "archive":
		failed.emit(kind, "Сервер не предоставляет этот раздел (HTTP 404). Проверьте, что запущен обновлённый сервер Б5. Тренировка и сохранённые отчёты доступны.")
		return
	if not data is Dictionary or data.get("api_version") != "v1" or data.get("ok") != true or code < 200 or code >= 300:
		var message := str(data.get("message", "Некорректный ответ сервера.")) if data is Dictionary else "Некорректный ответ сервера."
		failed.emit(kind, "HTTP %s · %s" % [code, message])
		return
	var field := "report" if kind == "archive" else kind
	var value: Variant = data if kind in ["leaderboard", "notifications"] else data.get(field)
	if not validate(kind, value, parameters):
		failed.emit(kind, "Структура ответа не соответствует подключённому формату. Данные не показаны; ожидается контракт Б5.")
		return
	received.emit(kind, value)

func validate(kind: String, value: Variant, parameters: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	if kind == "archive":
		return value.get("trip_id") == parameters.get("trip_id") and value.get("summary") is String and value.get("recommendation") is String and value.get("scenario_id") is String and value.get("scenario_version") is String and _integer(value.get("state_version"), 1) and session._valid_history(value.get("history")) and session._valid_scales(value.get("scales")) and session._valid_facts(value.get("facts")) and session._strings(value.get("critical_marks")) and valid_report_extension(value)
	if kind == "profile":
		if value.get("player_id") != session.player_id or not value.get("display_name") is String or not _integer(value.get("total_points")) or not _integer(value.get("completed_trips")):
			return false
		if not _skills(value.get("competencies"), false) or not value.get("achievements") is Array or value.achievements.size() != 3 or not value.get("report_ids") is Array or not value.get("best_results") is Array or not value.get("content") is Array:
			return false
		var seen: Array = []
		for item in value.achievements:
			if not item is Dictionary or item.get("id") not in ["first_trip", "safety_resolved", "checked_before_promise"] or item.id in seen or not item.get("name") is String or not item.get("earned") is bool:
				return false
			seen.append(item.id)
		for id in value.report_ids:
			if not id is String or id.length() != 32 or not id.is_valid_hex_number():
				return false
		for item in value.best_results:
			if not item is Dictionary or not item.get("scenario_id") is String or not item.get("scenario_version") is String or not _integer(item.get("points")) or not item.get("trip_id") in value.report_ids:
				return false
		var content_ids: Array = []
		for item in value.content:
			if not item is Dictionary or not item.get("id") is String or item.id in content_ids or not item.get("unlocked") is bool or not item.get("playable") is bool or not item.get("status") is String:
				return false
			content_ids.append(item.id)
		return "carriage-3" in content_ids
	if not _page(value, parameters):
		return false
	if kind == "leaderboard":
		if value.get("scope") != parameters.get("scope") or not value.get("scope_id") is String:
			return false
		for entry in value.entries:
			if not entry is Dictionary or not _integer(entry.get("rank"), 1) or not entry.get("display_name") is String or not _number(entry.get("total_points")) or not entry.get("is_demo") is bool or not entry.get("is_self") is bool:
				return false
		return true
	if kind == "notifications":
		for entry in value.notifications:
			if not entry is Dictionary or not entry.get("id") is String or not entry.get("title") is String or not entry.get("message") is String or not entry.get("created_at") is String or not entry.get("carriage_id") is String or not entry.get("content_status") is String:
				return false
		return true
	return false

func _number(value: Variant) -> bool:
	return session._number(value)

func _integer(value: Variant, minimum: int = 0) -> bool:
	return _number(value) and value >= minimum and value == floor(value)

func _page(value: Dictionary, parameters: Dictionary) -> bool:
	var entries: Variant = value.get("entries", value.get("notifications"))
	if not entries is Array or not _integer(value.get("total")) or not _integer(value.get("page"), 1) or value.page != parameters.get("page") or value.get("page_size") != PAGE_SIZE:
		return false
	var remaining := maxi(0, int(value.total) - (int(value.page) - 1) * PAGE_SIZE)
	return entries.size() == mini(PAGE_SIZE, remaining)

func _skills(value: Variant, report: bool) -> bool:
	if not value is Array or value.size() != 3:
		return false
	var ids: Array = []
	for item in value:
		if not item is Dictionary or item.get("id") not in ["communication", "safety", "prioritization"] or item.id in ids or not item.get("name") is String or not _integer(item.get("points")):
			return false
		ids.append(item.id)
		if report and (not _integer(item.get("max_points")) or item.points > item.max_points or not item.get("evidence") is Array):
			return false
	return true

func valid_report_extension(value: Dictionary) -> bool:
	if value.has("incidents"):
		if not value.incidents is Array:
			return false
		for item in value.incidents:
			if not item is Dictionary or not item.get("id") is String or not item.get("text") is String or not item.get("state") is String:
				return false
	if value.has("events"):
		if not value.events is Array:
			return false
		for item in value.events:
			if not item is Dictionary:
				return false
	for entry in value.get("history", []):
		if not entry.get("competency_evidence", []) is Array:
			return false
		for item in entry.get("competency_evidence", []):
			if not item is Dictionary:
				return false
	if not value.has("points"):
		return not value.has("report_version") # Legacy reports remain readable.
	if not value.points is Dictionary or not _skills(value.get("competencies"), true):
		return false
	for key in ["earned", "awarded", "previous_total", "total_after"]:
		if not _integer(value.points.get(key)):
			return false
	if not value.get("scenario_scores") is Array:
		return false
	for item in value.scenario_scores:
		if not item is Dictionary or not item.get("incident_id") is String or not item.get("scenario_version") is String:
			return false
		for key in ["points", "max_points", "awarded", "previous_best"]:
			if not _integer(item.get(key)):
				return false
	for item in value.competencies:
		for evidence in item.evidence:
			if not evidence is Dictionary or not evidence.get("reason") is String or not evidence.get("history_indices") is Array or not evidence.get("event_ids") is Array or not evidence.get("incident_id") is String:
				return false
			for index in evidence.history_indices:
				if not _integer(index) or index >= value.history.size():
					return false
			for id in evidence.event_ids:
				var found := false
				for event in value.get("events", []):
					if event.get("id") == id:
						found = true
				if not found:
					return false
	return true
