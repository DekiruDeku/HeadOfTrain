extends Node
## Transport only. The server owns transitions, consequences and scores.
signal changed
signal state_received(source: String)
signal report_received

const PLAYER_KEY := "hot.demo_player_id.v1"
const SESSION_KEY := "hot.session.v1"
const SAVE_PATH := "user://session-v1.json"
const Crew = preload("res://scripts/crew_state.gd")
var player_id := ""
var trip_id := ""
var trip: Dictionary = {}
var report: Dictionary = {}
var saved_reports: Array = []
var pending_post: Dictionary = {}
var busy := false
var ready_for_input := false
var storage_ok := false
var message := "Восстанавливаем сохранённую попытку…"
var error_code := ""
var notice := ""
var _kind := ""
var _source := "restore"
@onready var http: HTTPRequest = $HTTPRequest

func bootstrap() -> void:
	print("A2 session: restoring")
	if busy:
		return
	ready_for_input = false
	if _load_session():
		retry()

func retry() -> void:
	if busy:
		return
	if not storage_ok:
		bootstrap()
		return
	error_code = ""
	_source = "restore"
	if not pending_post.is_empty():
		var restored_source := str(pending_post.get("source", "restore"))
		if restored_source in ["assignments", "dialog/open", "dialog/close", "time"]:
			_source = restored_source
		_send("post", pending_post.path, pending_post.body)
	else:
		_send("current", "/api/trips/current")

func start_attempt(condition: String, new_attempt: bool) -> void:
	if not _can_submit():
		return
	_cancel_poll()
	_source = "start"
	_post("/api/trips/start", {"request_id": _uuid(), "luggage_space": condition, "new_attempt": new_attempt, "simulation_mode": "full_b4"})

func choose(incident_id: String, action_id: String) -> void:
	if not _can_submit() or trip.get("status") != "in_progress":
		return
	_cancel_poll()
	_source = "action"
	_post("/api/trips/%s/actions" % trip.trip_id, {
		"request_id": _uuid(), "expected_state_version": int(trip.state_version),
		"incident_id": incident_id, "node_id": trip.node_id, "action_id": action_id
	})

func _post(path: String, body: Dictionary) -> void:
	# Save the EXACT serialized body before sending. Never reconstruct a retry.
	pending_post = {"path": path, "body": JSON.stringify(body), "source": _source}
	if not _save_session():
		return
	notice = ""
	_send("post", path, pending_post.body)

func assign(incident_id: String, staff_id: String) -> void:
	_crew_command("assignments", {"incident_id": incident_id, "staff_id": staff_id})

func set_time_speed(speed: int) -> void:
	_crew_command("time", {"speed": speed})

func open_dialog(incident_id: String) -> void:
	_crew_command("dialog/open", {"incident_id": incident_id})

func close_dialog() -> void:
	if trip.get("simulation_mode") in ["crew_b3", "full_b4"]:
		_crew_command("dialog/close", {"incident_id": trip.dialog.incident_id})
	else:
		_crew_command("dialog/close", {"dialog_id": trip.get("active_dialog_id")})

func _crew_command(operation: String, fields: Dictionary) -> void:
	if not _can_submit() or not Crew.enabled(trip):
		return
	_cancel_poll()
	_source = operation
	fields.request_id = _uuid()
	fields.expected_state_version = int(trip.state_version)
	_post("/api/trips/%s/%s" % [trip.trip_id, operation], fields)

func is_polling() -> bool:
	return busy and _kind == "current" and _source == "poll"

func _can_submit() -> bool:
	return ready_for_input and pending_post.is_empty() and (not busy or is_polling())

func _cancel_poll() -> void:
	# A background read must not swallow a click. Commands still use the last
	# confirmed version; the server can reject a stale version normally.
	if is_polling():
		http.cancel_request()
		busy = false

func _on_poll() -> void:
	if busy or not ready_for_input or not error_code.is_empty() or not pending_post.is_empty() or trip.get("status") != "in_progress" or not Crew.enabled(trip):
		return
	_source = "poll"
	_send("current", "/api/trips/current")

func _origin() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.location.origin"))
	return OS.get_environment("HEAD_OF_TRAIN_API").trim_suffix("/") if OS.has_environment("HEAD_OF_TRAIN_API") else "http://127.0.0.1:8765"

func _send(kind: String, path: String, body: String = "") -> void:
	print("A2 request: " + kind)
	busy = true
	if _source != "poll":
		ready_for_input = false
	_kind = kind
	if _source != "poll":
		message = "Ждём подтверждение сервера…" if kind == "post" else "Загружаем сохранённое состояние…"
	if kind == "report":
		message = "Загружаем сохранённый разбор…"
	changed.emit()
	var method := HTTPClient.METHOD_POST if kind == "post" else HTTPClient.METHOD_GET
	var err := http.request(_origin() + path, ["Content-Type: application/json", "X-Demo-Player: " + player_id], method, body)
	if err != OK:
		_fail("connection", "Не удалось отправить запрос. Проверьте связь и нажмите «Восстановить связь».")

func _on_response(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	print("A2 response: %s HTTP %s transport %s" % [_kind, code, result])
	busy = false
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code >= 500 or code == 0:
		_fail("connection", "Нет подтверждения сервера. Проверьте соединение и нажмите «Восстановить связь».")
		return
	if not data is Dictionary or data.get("api_version") != "v1" or not data.get("ok") is bool:
		_fail("invalid_response", "Сервер прислал непонятный ответ. Состояние не подтверждено. Повторите запрос.")
		return
	if code < 200 or code >= 300 or not data.ok:
		_handle_error(code, data)
		return
	if _kind == "report":
		if not _valid_report(data.get("report")):
			_fail("invalid_report", "Разбор не соответствует попытке. Повторите загрузку.")
			return
		report = data.report
		if not remember_report(report):
			return
		ready_for_input = true
		message = "Разбор получен из сохранённой попытки."
		changed.emit()
		report_received.emit()
		return
	data.trip = Crew.from_wire(data.get("trip"))
	if not _valid_trip(data.get("trip")):
		_fail("invalid_state", "Ответ не содержит полного состояния сценария. Повторите загрузку.")
		return
	if _kind == "post":
		if not _valid_acknowledgement(data):
			_fail("invalid_confirmation", "Сервер не подтвердил именно этот запрос. Выбор остаётся неподтверждённым; повторите его.")
			return
		# A valid replay may still be older than current. Always GET next.
		trip_id = data.trip.trip_id
		pending_post = {}
		if _save_session():
			_send("current", "/api/trips/current")
		return
	trip = data.trip
	$Poll.wait_time = 0.25 if int(trip.get("time_speed",1)) > 1 else 1.0
	trip_id = trip.trip_id
	report = {}
	if not _save_session():
		return
	error_code = ""
	message = "Состояние подтверждено сервером."
	if trip.has("fixture_label"):
		message = "ФИКСТУРЫ А3 · HTTP-стенд · Б3 ещё не подключён · результаты не сохраняются."
	state_received.emit(_source)
	if trip.status == "completed":
		_send("report", "/api/trips/%s/report" % trip_id)
	else:
		ready_for_input = true
		changed.emit()

func _handle_error(code: int, data: Dictionary) -> void:
	var server_error := str(data.get("error", "unknown_error"))
	if _kind == "current" and code == 404 and server_error == "no_current_trip":
		trip = {}
		report = {}
		ready_for_input = true
		error_code = ""
		message = "Связь установлена. Можно начать тренировку."
		state_received.emit("empty")
		changed.emit()
		return
	# Definite rejections, not unknown POST outcomes.
	if code in [409, 422] and _kind == "post":
		pending_post = {}
		notice = "Запрос не принят (%s). %s Проверьте актуальное состояние." % [server_error, str(data.get("message", ""))]
		if _save_session():
			_source = "restore"
			_send("current", "/api/trips/current")
		return
	var detail := str(data.get("message", "Запрос отклонён сервером."))
	_fail(server_error, "Ошибка сервера HTTP %s (%s). %s Данные игрока сохранены." % [code, server_error, detail])

func _fail(reason: String, detail: String) -> void:
	print("A2 error: " + reason)
	busy = false
	ready_for_input = false
	error_code = reason
	message = detail
	if not pending_post.is_empty() and storage_ok:
		message += " Неподтверждённый запрос сохранён; повторим его без изменений."
	changed.emit()

func _uuid() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("crypto.randomUUID().replaceAll('-', '')"))
	# Crypto is a nonvisual data object, never a scene/UI factory.
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	return bytes.hex_encode()

func _load_session() -> bool:
	var raw := ""
	if OS.has_feature("web"):
		var value: Variant = JavaScriptBridge.eval("""(() => { try {
			return JSON.stringify({player:localStorage.getItem('hot.demo_player_id.v1'),session:localStorage.getItem('hot.session.v1')});
		} catch(e) { return null; } })()""")
		if value == null:
			_fail("storage", "Браузер запретил локальное сохранение. Разрешите хранилище для этой страницы и повторите. Запрос не отправлен.")
			return false
		var saved: Dictionary = JSON.parse_string(str(value))
		player_id = str(saved.player) if saved.player != null else ""
		raw = str(saved.session) if saved.session != null else ""
	elif FileAccess.file_exists(SAVE_PATH):
		raw = FileAccess.get_file_as_string(SAVE_PATH)
	if not raw.is_empty():
		var state: Variant = JSON.parse_string(raw)
		if not state is Dictionary or not state.get("player_id") is String or not state.get("pending", {}) is Dictionary:
			_fail("storage", "Локальная запись повреждена. Сохраните её для диагностики; автоматический сброс игрока отключён.")
			return false
		if not player_id.is_empty() and player_id != state.player_id:
			_fail("storage", "Локальные записи принадлежат разным игрокам. Автоматический сброс отключён.")
			return false
		player_id = state.player_id
		trip_id = str(state.get("trip_id", ""))
		saved_reports = []
		if state.get("reports") is Array:
			for item in state.reports:
				if item is Dictionary and item.get("trip_id") is String and item.trip_id.length() == 32 and item.trip_id.is_valid_hex_number() and item.get("completed_at") is String:
					saved_reports.append(item)
		pending_post = state.get("pending", {})
		if not pending_post.is_empty() and (not pending_post.get("path") is String or not pending_post.get("body") is String or not pending_post.path.begins_with("/api/trips/") or not JSON.parse_string(pending_post.body) is Dictionary):
			_fail("storage", "Сохранённый запрос повреждён. Он не отправлен; запись оставлена для диагностики.")
			return false
	if player_id.is_empty():
		player_id = _uuid()
	if player_id.length() != 32 or not player_id.is_valid_hex_number() or player_id != player_id.to_lower():
		_fail("storage", "Некорректный сохранённый ID игрока. Автоматическая замена отключена.")
		return false
	return _save_session()

func _save_session() -> bool:
	var raw := JSON.stringify({"player_id": player_id, "trip_id": trip_id, "pending": pending_post, "reports": saved_reports})
	if OS.has_feature("web"):
		var script := "(() => { try { const p=%s, s=%s; localStorage.setItem('%s', p); localStorage.setItem('%s', s); return localStorage.getItem('%s')===p && localStorage.getItem('%s')===s; } catch(e) { return false; } })()" % [JSON.stringify(player_id), JSON.stringify(raw), PLAYER_KEY, SESSION_KEY, PLAYER_KEY, SESSION_KEY]
		var stored: Variant = JavaScriptBridge.eval(script)
		# The bundled Web template returns JS booleans as integers.
		storage_ok = bool(stored)
	else:
		var file := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
		storage_ok = file != null
		if storage_ok:
			file.store_string(raw)
			file.flush()
			storage_ok = file.get_error() == OK
			file.close()
			if storage_ok:
				storage_ok = DirAccess.rename_absolute(SAVE_PATH + ".tmp", SAVE_PATH) == OK
	if not storage_ok:
		_fail("storage", "Не удалось сохранить данные. Освободите место или разрешите хранилище и повторите.")
	return storage_ok

func remember_report(value: Dictionary) -> bool:
	for entry in saved_reports:
		if entry.trip_id == value.trip_id:
			return true
	# Only links are cached. Scores and report content always come from the server.
	saved_reports.push_front({"trip_id": value.trip_id, "completed_at": str(value.get("completed_at", ""))})
	return _save_session()

func _valid_history(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry in value:
		if not entry is Dictionary or not entry.get("selected_text") is String or not entry.get("explanation") is String or not entry.get("effects") is Dictionary or not entry.get("request_id") is String:
			return false
		var effects: Dictionary = entry.effects
		for field in ["loyalty_delta", "safety_delta"]:
			if effects.has(field) and not _number(effects[field]):
				return false
		if effects.has("facts") and not _valid_facts(effects.facts):
			return false
		if effects.has("critical_marks") and not _strings(effects.critical_marks):
			return false
	return true

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _strings(value: Variant) -> bool:
	if not value is Array:
		return false
	for item in value:
		if not item is String:
			return false
	return true

func _valid_facts(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for field in ["aisle_clear", "alternative_checked"]:
		if value.has(field) and not value[field] is bool:
			return false
	return value.get("placement") in [null, "regular", "alternative"]

func _valid_scales(value: Variant) -> bool:
	if not value is Dictionary or not _number(value.get("safety")) or not value.get("loyalty") is Dictionary or (value.get("overall_loyalty") != null and not _number(value.overall_loyalty)):
		return false
	for amount in value.loyalty.values():
		if not _number(amount):
			return false
	return true

func _valid_trip(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if not value.get("trip_id") is String or not value.get("node_id") is String or not _number(value.get("state_version")):
		return false
	if value.trip_id.length() != 32 or not value.trip_id.is_valid_hex_number() or value.trip_id != value.trip_id.to_upper():
		return false
	if value.state_version < 1 or value.state_version != int(value.state_version) or value.get("status") not in ["in_progress", "completed"]:
		return false
	if not value.get("conditions") is Dictionary or value.conditions.get("luggage_space") not in ["free", "occupied"] or not _valid_scales(value.get("scales")) or not _valid_facts(value.get("facts")) or not _valid_history(value.get("history")):
		return false
	if not value.get("incidents") is Array or value.incidents.is_empty() or not value.get("carriages") is Array or value.carriages.is_empty():
		return false
	if not value.get("staff") is Array:
		return false
	for carriage in value.carriages:
		if not carriage is Dictionary or not carriage.get("id") is String or not carriage.get("name") is String:
			return false
	for incident in value.incidents:
		if not incident is Dictionary or not incident.get("id") is String or not incident.get("marker_id") is String or not incident.get("text") is String or incident.get("state") not in ["waiting", "en_route", "resolving", "completed"]:
			return false
	if Crew.enabled(value):
		if not Crew.valid(value):
			return false
		if not value.paused or value.get("pause_reason") == "user":
			return true
	if value.status == "in_progress":
		var dialog: Variant = value.get("dialog")
		if not dialog is Dictionary or not dialog.get("text") is String or not dialog.get("options") is Array or dialog.options.is_empty() or dialog.options.size() > 3:
			return false
		for option in dialog.options:
			if not option is Dictionary or not option.get("id") is String or not option.get("text") is String or not option.get("available") is bool:
				return false
	return true

func _valid_report(value: Variant) -> bool:
	return value is Dictionary and value.get("trip_id") == trip_id and value.get("state_version") == trip.get("state_version") and value.get("summary") is String and value.get("recommendation") is String and _valid_facts(value.get("facts")) and _valid_scales(value.get("scales")) and _valid_history(value.get("history")) and _strings(value.get("critical_marks")) and value.get("scenario_id") is String and value.get("scenario_version") is String and value.history == trip.history and value.facts == trip.facts and value.scales == trip.scales

func _valid_acknowledgement(data: Dictionary) -> bool:
	if pending_post.path == "/api/trips/start":
		return data.get("player_id") == player_id and data.get("status") == "started" and data.get("trip_id") == data.trip.trip_id
	var payload: Dictionary = JSON.parse_string(pending_post.body)
	for operation in ["assignments", "dialog/open", "dialog/close", "time"]:
		if pending_post.path == "/api/trips/%s/%s" % [data.trip.trip_id, operation]:
			if data.trip.get("simulation_mode") in ["crew_b3", "full_b4"]:
				return _valid_b3_command(data.trip, payload, operation)
			var ack: Variant = data.get("acknowledgement")
			if not ack is Dictionary or ack.get("request_id") != payload.request_id or ack.get("operation") != operation:
				return false
			for field in ["incident_id", "staff_id", "dialog_id"]:
				if payload.has(field) and ack.get(field) != payload[field]:
					return false
			return true
	if pending_post.path != "/api/trips/%s/actions" % data.trip.trip_id:
		return false
	for entry in data.trip.history:
		if entry.request_id == payload.request_id and entry.get("action_id") == payload.action_id and entry.get("node_before") == payload.node_id:
			return true
	return false

func _valid_b3_command(state: Dictionary, payload: Dictionary, operation: String) -> bool:
	# B3 returns the committed snapshot, not the draft acknowledgement envelope.
	# Exact HTTP body/path are retained for retries; a successful replay is followed by GET.
	if state.state_version <= payload.expected_state_version:
		return false
	if operation == "time":
		return state.get("time_speed") == payload.get("speed")
	for incident in state.incidents:
		if incident.id != payload.incident_id:
			continue
		if operation == "assignments":
			return incident.get("assigned_staff_id") == payload.staff_id and incident.state in ["en_route", "resolving"]
		if operation == "dialog/open":
			return state.paused and state.dialog is Dictionary and state.dialog.get("incident_id") == payload.incident_id
		return operation == "dialog/close" and state.get("pause_reason") != "dialog" and state.get("active_dialog_id") == null
	return false
