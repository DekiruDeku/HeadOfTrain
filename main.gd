extends Control
## A1: navigation and the existing API only. Every node is saved in a scene.

var pending := ""
var demo_requests: Array = []
var return_focus: Control
@onready var screens: TabContainer = $Screens
@onready var start: ScrollContainer = $Screens/StartScreen
@onready var trip: ScrollContainer = $Screens/TripScreen
@onready var decision: ScrollContainer = $Screens/Decision
@onready var debrief: ScrollContainer = $Screens/Debrief
@onready var http: HTTPRequest = $APIRequest

func _ready() -> void:
	demo_requests = JSON.parse_string(FileAccess.get_file_as_string("res://data/demo_requests.json"))
	_request("health")

func _api_origin() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.location.origin"))
	return OS.get_environment("HEAD_OF_TRAIN_API").trim_suffix("/") if OS.has_environment("HEAD_OF_TRAIN_API") else "http://127.0.0.1:8765"

func _request(action: String) -> void:
	if not pending.is_empty():
		return
	pending = action
	start.set_pending(action)
	var url := _api_origin() + ("/api/health" if action == "health" else "/api/trips/start")
	var method := HTTPClient.METHOD_GET if action == "health" else HTTPClient.METHOD_POST
	var error := http.request(url, ["Content-Type: application/json"], method, "" if action == "health" else "{}")
	if error != OK:
		pending = ""
		start.show_error("Не удалось отправить запрос. Повторите.")

func _on_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := pending
	pending = ""
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		start.show_error("Нет ответа. Проверьте связь и нажмите «Начать рейс» повторно.")
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or data.get("ok") != true:
		start.show_error("Некорректный ответ сервера. Повторите.")
		return
	if action == "start" and (not data.get("trip_id") is String or str(data.get("trip_id")).is_empty() or data.get("status") != "started"):
		start.show_error("Сервер не подтвердил рейс. Повторите.")
		return
	if action == "health":
		start.show_success("Связь установлена. Можно начинать.")
	else:
		var confirmation := "Рейс № %s · отправление подтверждено API" % str(data["trip_id"])
		start.show_success(confirmation)
		_open_trip(confirmation + ". Игровые данные — локальное демо.")
	print("API %s HTTP %s: %s" % [action, response_code, JSON.stringify(data)])

func _on_start() -> void:
	_request("start")

func _on_health() -> void:
	_request("health")

func _on_demo() -> void:
	_open_trip("Демо без запроса старта · данные не сохраняются")

func _open_trip(confirmation: String) -> void:
	trip.show_trip(demo_requests, confirmation)
	screens.current_tab = 1
	trip.scroll_vertical = 0

func _on_back_to_start() -> void:
	screens.current_tab = 0
	start.start_button.grab_focus()

func _on_request_selected(request_id: String) -> void:
	for data in demo_requests:
		if data["id"] == request_id:
			return_focus = get_viewport().gui_get_focus_owner()
			decision.present(data)
			screens.current_tab = 2
			decision.get_node("%Choice1").grab_focus()
			decision.scroll_vertical = 0
			return

func _on_choice_selected(request_id: String, choice_index: int) -> void:
	for data in demo_requests:
		if data["id"] == request_id:
			debrief.present(data["title"], data["choices"][choice_index])
			screens.current_tab = 3
			debrief.get_node("%Back").grab_focus()
			debrief.scroll_vertical = 0
			return

func _on_back_to_trip() -> void:
	screens.current_tab = 1
	if is_instance_valid(return_focus) and return_focus.is_visible_in_tree():
		return_focus.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and screens.current_tab >= 2:
		_on_back_to_trip()
		get_viewport().set_input_as_handled()
