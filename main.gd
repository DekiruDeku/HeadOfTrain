extends Control
## One scene, one carriage and real HTTP responses from the same-origin API.

const INK := Color("26352e")
const MUTED := Color("687168")
const GREEN := Color("38634e")
const RED := Color("a34835")

var brand: Label
var badge: Label
var heading: Label
var introduction: Label
var image_panel: Panel
var carriage: TextureRect
var caption: Label
var details: Panel
var eyebrow: Label
var trip_title: Label
var trip_description: Label
var start_button: Button
var status: Label
var footer: Label
var http: HTTPRequest
var pending := ""
var started := false


func _ready() -> void:
	_build_ui()
	http = HTTPRequest.new()
	http.timeout = 8.0
	http.body_size_limit = 65536
	add_child(http)
	http.request_completed.connect(_on_response)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_request("health")


func _label(text_value: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _box(color: Color, radius: int = 18) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box


func _build_ui() -> void:
	brand = _label("НР  /  НАЧАЛЬНИК РЕЙСА", 18)
	badge = _label("ПОДКЛЮЧАЕМСЯ", 13, MUTED)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading = _label("Ваш первый рейс", 46)
	introduction = _label("Всё начинается с одного вагона.", 20, MUTED)
	image_panel = Panel.new()
	image_panel.add_theme_stylebox_override("panel", _box(Color("61665b")))
	image_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image_panel)
	carriage = TextureRect.new()
	carriage.texture = preload("res://assets/carriage.png")
	carriage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	carriage.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	carriage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(carriage)
	caption = _label("01  /  ВАГОН «СТАНДАРТ»", 14, MUTED)
	details = Panel.new()
	details.add_theme_stylebox_override("panel", _box(Color("fafaf5")))
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(details)
	eyebrow = _label("ПРОБНЫЙ РЕЙС", 13, GREEN)
	trip_title = _label("Готовы к\nотправлению?", 30)
	trip_description = _label("Начните рейс, чтобы получить подтверждение отправления.", 18, MUTED)
	start_button = Button.new()
	start_button.text = "Начать рейс"
	start_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	start_button.add_theme_font_size_override("font_size", 20)
	start_button.add_theme_color_override("font_color", Color.WHITE)
	start_button.add_theme_color_override("font_hover_color", Color.WHITE)
	start_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	start_button.add_theme_color_override("font_disabled_color", Color("eeeee8"))
	start_button.add_theme_stylebox_override("normal", _box(GREEN, 12))
	start_button.add_theme_stylebox_override("hover", _box(Color("47765d"), 12))
	start_button.add_theme_stylebox_override("pressed", _box(Color("264a39"), 12))
	start_button.add_theme_stylebox_override("disabled", _box(Color("819486"), 12))
	var focus_style := _box(Color.TRANSPARENT, 12)
	focus_style.border_color = Color("bf8544")
	focus_style.set_border_width_all(3)
	start_button.add_theme_stylebox_override("focus", focus_style)
	start_button.pressed.connect(_on_start_pressed)
	add_child(start_button)
	status = _label("Проверяем связь с сервером…", 15, MUTED)
	footer = _label("ПРОТОТИП 01     •     Подготовка к отправлению", 13, MUTED)


func _place(control: Control, x: float, y: float, w: float, h: float) -> void:
	control.position = Vector2(x, y)
	control.size = Vector2(w, h)


func _layout() -> void:
	# Switch logical design size as the browser rotates/resizes. Expand preserves
	# aspect ratio; the carriage itself always uses KEEP_ASPECT_CENTERED.
	var pixels := DisplayServer.window_get_size()
	var portrait := float(pixels.x) / maxf(pixels.y, 1.0) < 0.85
	var design_size := Vector2i(390, 720) if portrait else Vector2i(1152, 720)
	if get_window().content_scale_size != design_size:
		get_window().content_scale_size = design_size
		return
	var viewport_size := get_viewport_rect().size
	var w := viewport_size.x
	var h := viewport_size.y
	var narrow := w < 700.0
	var margin := 22.0 if narrow else 48.0
	var content_width := w - margin * 2.0
	brand.add_theme_font_size_override("font_size", 15 if narrow else 18)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if narrow else HORIZONTAL_ALIGNMENT_RIGHT
	_place(brand, margin, 25, content_width if narrow else 440.0, 26)
	_place(badge, margin if narrow else w - 328.0, 58 if narrow else 27, content_width if narrow else 280.0, 24)
	heading.add_theme_font_size_override("font_size", 32 if narrow else 46)
	_place(heading, margin, 100 if narrow else 104, content_width, 58)
	_place(introduction, margin, 148 if narrow else 167, content_width, 42)
	var image_width := content_width if narrow else (content_width - 28.0) * 0.66
	var image_height := minf(image_width / 1.5, maxf(120.0, h - (580.0 if narrow else 350.0)))
	var image_y := 195.0 if narrow else 248.0
	_place(image_panel, margin, image_y, image_width, image_height)
	_place(carriage, margin, image_y, image_width, image_height)
	_place(caption, margin, image_y + image_height + 12.0, image_width, 24)
	var panel_x := margin if narrow else margin + image_width + 28.0
	var panel_y := image_y + image_height + 44.0 if narrow else image_y
	var panel_w := content_width if narrow else content_width - image_width - 28.0
	var panel_h := 286.0 if narrow else image_height
	_place(details, panel_x, panel_y, panel_w, panel_h)
	var inset := 22.0 if narrow else 26.0
	var inner_w := panel_w - inset * 2.0
	_place(eyebrow, panel_x + inset, panel_y + 22.0, inner_w, 24)
	trip_title.text = ("Рейс начат" if started else "Готовы к отправлению?") if narrow else ("Счастливого\nпути!" if started else "Готовы к\nотправлению?")
	trip_title.add_theme_font_size_override("font_size", 23 if narrow else 30)
	_place(trip_title, panel_x + inset, panel_y + 55.0, inner_w, 42.0 if narrow else 86.0)
	_place(trip_description, panel_x + inset, panel_y + (103.0 if narrow else 153.0), inner_w, 62.0 if narrow else 80.0)
	_place(start_button, panel_x + inset, panel_y + panel_h - 110.0, inner_w, 56.0)
	_place(status, panel_x + inset, panel_y + panel_h - 43.0, inner_w, 40.0)
	var footer_y := maxf(h - 36.0, panel_y + panel_h + 16.0)
	_place(footer, margin, footer_y, content_width, 24)


func _api_origin() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.location.origin"))
	return OS.get_environment("HEAD_OF_TRAIN_API").trim_suffix("/") if OS.has_environment("HEAD_OF_TRAIN_API") else "http://127.0.0.1:8765"


func _request(action: String) -> void:
	if not pending.is_empty():
		return
	pending = action
	start_button.disabled = true
	var url := _api_origin() + ("/api/health" if action == "health" else "/api/trips/start")
	var method := HTTPClient.METHOD_GET if action == "health" else HTTPClient.METHOD_POST
	var error := http.request(url, ["Content-Type: application/json"], method, "" if action == "health" else "{}")
	if error != OK:
		pending = ""
		_show_error("Не удалось отправить запрос. Повторите.")


func _on_start_pressed() -> void:
	if started:
		started = false
		start_button.text = "Начать рейс"
		trip_description.text = "Начните рейс, чтобы получить подтверждение отправления."
		_layout()
	status.text = "Ждём подтверждение сервера…"
	status.add_theme_color_override("font_color", MUTED)
	_request("start")


func _on_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := pending
	pending = ""
	start_button.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_show_error("Нет ответа. Нажмите, чтобы повторить.")
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or data.get("ok") != true:
		_show_error("Некорректный ответ сервера. Повторите.")
		return
	if action == "start" and (not data.get("trip_id") is String or data.get("status") != "started"):
		_show_error("Сервер не подтвердил рейс. Повторите.")
		return
	badge.text = "СЕРВЕР НА СВЯЗИ"
	badge.add_theme_color_override("font_color", GREEN)
	status.add_theme_color_override("font_color", GREEN)
	if action == "health":
		status.text = "Связь установлена. Можно начинать."
	else:
		started = true
		start_button.text = "Начать ещё раз"
		trip_description.text = "Отправление подтверждено.\nВагон готов к первому рейсу."
		status.text = "Рейс № %s · ответ получен" % str(data["trip_id"])
		_layout()
	# Real response logging makes browser smoke tests independently verifiable.
	print("API %s HTTP %s: %s" % [action, response_code, JSON.stringify(data)])


func _show_error(message: String) -> void:
	start_button.disabled = false
	badge.text = "НЕТ СВЯЗИ"
	badge.add_theme_color_override("font_color", RED)
	status.text = message
	status.add_theme_color_override("font_color", RED)
