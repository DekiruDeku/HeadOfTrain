extends Control
signal trip_completed(trip_id: String)
const Crew = preload("res://scripts/crew_state.gd")
var after_close_tab := 1
var announced_completion := ""
var displayed_report: Dictionary = {}
var requested_report_id := ""
const MENU_PANEL = preload("res://theme/menu_empty_panel.tres")
var _screen_tween: Tween
var _last_screen: Control
var _menu_profile_requested := false
var _leaving_decision := false
var _decision_destination := 1
## All screens and components are saved in main.tscn and nested scenes.
@onready var screens: TabContainer = %Screens
@onready var start = %StartScreen
@onready var trip = %TripScreen
@onready var decision = %Decision
@onready var debrief = %Debrief
@onready var api = $SessionAPI
@onready var progress_api = $ProgressAPI
@onready var report_screen = %Report
@onready var profile_screen = %Profile
@onready var leaderboard_screen = %Leaderboard
@onready var notifications_screen = %Notifications

func _ready() -> void:
	decision.retry_requested.connect(api.retry)
	trip.time_speed_requested.connect(api.set_time_speed)
	trip.retry_requested.connect(api.retry)
	start.profile_requested.connect(_open_profile)
	report_screen.profile_requested.connect(_open_profile)
	profile_screen.leaderboard_requested.connect(_open_leaderboard)
	profile_screen.notifications_requested.connect(_open_notifications)
	leaderboard_screen.profile_requested.connect(_open_profile)
	leaderboard_screen.notifications_requested.connect(_open_notifications)
	notifications_screen.profile_requested.connect(_open_profile)
	notifications_screen.leaderboard_requested.connect(_open_leaderboard)
	notifications_screen.report_requested.connect(_open_archived_report)
	start.leaderboard_requested.connect(_open_leaderboard)
	start.notifications_requested.connect(_open_notifications)
	screens.tab_changed.connect(_on_screen_changed)
	_on_screen_changed(screens.current_tab)
	if not has_meta("scene_test"):
		api.bootstrap()

func _on_screen_changed(index: int) -> void:
	if index == 4: report_screen.reduced_motion = start.reduced_motion
	if index == 5: profile_screen.reduced_motion = start.reduced_motion
	if index == 6: leaderboard_screen.reduced_motion = start.reduced_motion
	if index == 7: notifications_screen.reduced_motion = start.reduced_motion
	# Decision is a modal over the same live trip, with its own input and animation.
	trip.set_process_input(index == 1)
	trip.visible = index in [1, 2]
	screens.mouse_filter = Control.MOUSE_FILTER_IGNORE if index == 1 else Control.MOUSE_FILTER_STOP
	if index == 2:
		var focused := get_viewport().gui_get_focus_owner()
		if focused: focused.release_focus()
	$Layout/Connection.visible = index not in [0, 1, 2, 3, 4, 5, 6, 7]
	$Layout/Navigation.visible = index not in [0, 1, 2, 3, 4, 5, 6, 7]
	if index in [0, 1, 2, 3, 4, 5, 6, 7]:
		screens.add_theme_stylebox_override("panel", MENU_PANEL)
	else:
		screens.remove_theme_stylebox_override("panel")
	if _screen_tween and _screen_tween.is_valid():
		_screen_tween.kill()
	if is_instance_valid(_last_screen):
		_last_screen.modulate.a = 1.0
	_last_screen = screens.get_current_tab_control()
	# StartScreen owns its entrance. Other existing screens share a short fade.
	if index not in [0, 1, 2, 3, 4, 5, 6, 7] and not start.reduced_motion:
		_last_screen.modulate.a = 0.0
		_screen_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_screen_tween.tween_property(_last_screen, "modulate:a", 1.0, 0.24)

func _show_screen(index: int) -> void:
	if screens.current_tab == 2 and index != 2:
		_decision_destination = index
		if _leaving_decision: return
		_leaving_decision = true
		await decision.dismiss()
		_leaving_decision = false
		screens.current_tab = _decision_destination
		return
	screens.current_tab = index

func _on_api_changed() -> void:
	%ConnectionText.text = api.message + ("\n" + api.notice if not api.notice.is_empty() else "")
	%ConnectionText.theme_type_variation = &"Error" if not api.error_code.is_empty() else &"Small"
	%Retry.visible = not api.error_code.is_empty()
	%Retry.disabled = api.busy
	var locked: bool = not api.ready_for_input or (api.busy and not api.is_polling())
	start.set_state(api.trip, api.message, locked)
	start.set_connection_error(not api.error_code.is_empty())
	if api.ready_for_input and not _menu_profile_requested and not has_meta("scene_test"):
		_menu_profile_requested = true
		progress_api.profile()
	decision.set_locked(locked)
	trip.set_locked(locked)
	trip.set_connection_message(api.message if not api.error_code.is_empty() else "")
	decision.set_connection_message(api.message if not api.error_code.is_empty() else "")
	debrief.set_locked(locked)
	report_screen.set_locked(locked)
	report_screen.reduced_motion = start.reduced_motion

func _on_state_received(source: String) -> void:
	if api.trip.is_empty():
		_show_screen(0)
		return
	trip.show_trip(api.trip)
	if source == "poll" and (screens.current_tab >= 4 or (screens.current_tab == 3 and debrief.final_report)) and api.trip.status != "completed":
		return
	if Crew.enabled(api.trip) and api.trip.status == "in_progress":
		if api.trip.paused and api.trip.get("pause_reason") != "user":
			for incident in api.trip.incidents:
				if incident.id == api.trip.dialog.incident_id:
					decision.present(api.trip, incident, source != "poll")
					_show_screen(2)
		elif source == "dialog/close":
			_show_screen(after_close_tab)
		elif source != "poll" or screens.current_tab == 2:
			_show_screen(1)
		return
	if api.trip.status == "completed":
		if announced_completion != api.trip.trip_id:
			announced_completion = api.trip.trip_id
			trip_completed.emit(api.trip.trip_id)
		# Do not show an old report while the saved report is loading.
		_show_screen(1)
	elif source == "action":
		debrief.present_effect(api.trip.history.back(), api.trip)
		_show_screen(3)
	else:
		_show_screen(1)
	trip.scroll_vertical = 0

func _on_report_received() -> void:
	if not progress_api.valid_report_extension(api.report):
		_on_progress_failed("archive", "Отчёт содержит неподдерживаемые данные. Требуется согласованный контракт сервера.")
		return
	displayed_report = api.report.duplicate(true)
	# Historical B1-B3 report payloads omit incident snapshots.
	if not displayed_report.has("incidents"):
		displayed_report.incidents = api.trip.get("incidents", []).duplicate(true)
	requested_report_id = displayed_report.trip_id
	report_screen.present(displayed_report)
	report_screen.present_archive(api.saved_reports)
	_show_screen(4)

func _on_start() -> void:
	if not api.trip.is_empty() and api.trip.status == "in_progress":
		_on_back_to_trip()
		return
	api.start_attempt(start.selected_condition(), not api.trip.is_empty())

func _on_health() -> void:
	api.retry()

func _on_back_to_start() -> void:
	if Crew.enabled(api.trip) and api.trip.get("paused", false) and api.trip.get("pause_reason") != "user":
		after_close_tab = 0
		api.close_dialog()
		return
	_show_screen(0)

func _on_request_selected(incident_id: String) -> void:
	if not api.ready_for_input:
		return
	if api.trip.status == "completed":
		if not api.report.is_empty():
			_on_report_received()
		return
	for incident in api.trip.incidents:
		if incident.id == incident_id:
			if Crew.enabled(api.trip):
				if incident.state == "resolving" and incident.type != "service":
					api.open_dialog(incident_id)
				return
			decision.present(api.trip, incident)
			_show_screen(2)
			return

func _on_choice_selected(incident_id: String, action_id: String) -> void:
	api.choose(incident_id, action_id)

func _on_back_to_trip() -> void:
	# Profile, ranking and notifications can be opened before the first attempt.
	# Escape must not expose an unbound trip screen with placeholder data.
	if api.trip.is_empty():
		_on_back_to_start()
		return
	if Crew.enabled(api.trip) and api.trip.get("paused", false) and api.trip.get("pause_reason") != "user":
		after_close_tab = 1
		api.close_dialog()
		return
	_show_screen(1)

func _on_assignment_requested(incident_id: String, staff_id: String) -> void:
	api.assign(incident_id, staff_id)

func _on_continue() -> void:
	if debrief.final_report:
		_on_back_to_start()
	elif api.trip.get("status") == "in_progress":
		_on_request_selected(api.trip.incidents[0].id)
	else:
		_on_back_to_start()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and screens.current_tab >= 2:
		_on_back_to_trip()
		get_viewport().set_input_as_handled()

func _open_reports() -> void:
	_show_screen(4)
	report_screen.present_archive(api.saved_reports)
	if displayed_report.is_empty() and not api.report.is_empty():
		_on_report_received()
	elif displayed_report.is_empty():
		report_screen.failed("Завершённых отчётов в этой сессии ещё нет. Выберите сохранённый рейс ниже.")

func _return_to_report() -> void:
	_show_screen(4)

func _open_debrief(request_id: String = "") -> void:
	if displayed_report.is_empty():
		return
	debrief.present_report(displayed_report)
	debrief.select_evidence(request_id)
	_show_screen(3)

func _open_archived_report(id: String) -> void:
	requested_report_id = id
	_show_screen(4)
	progress_api.archived_report(id)

func _refresh_report() -> void:
	if not requested_report_id.is_empty():
		_open_archived_report(requested_report_id)
	else:
		_open_reports()

func _open_profile() -> void:
	_show_screen(5)
	progress_api.profile()

func _open_leaderboard() -> void:
	leaderboard_screen.reduced_motion = start.reduced_motion
	_show_screen(6)
	_load_leaderboard(leaderboard_screen.scope, 1)

func _load_leaderboard(scope: String, page: int) -> void:
	leaderboard_screen.requested_page = page
	progress_api.leaderboard(scope, page)

func _open_notifications() -> void:
	notifications_screen.reduced_motion = start.reduced_motion
	_show_screen(7)
	_load_notifications(1)
	progress_api.profile()

func _load_notifications(page: int) -> void:
	notifications_screen.requested_page = page
	progress_api.notifications(page)

func _progress_screen(kind: String):
	return {"archive": report_screen, "profile": profile_screen, "leaderboard": leaderboard_screen, "notifications": notifications_screen}[kind]

func _on_progress_loading(kind: String) -> void:
	_progress_screen(kind).loading()

func _on_progress_failed(kind: String, message: String) -> void:
	_progress_screen(kind).failed(message)

func _on_progress_received(kind: String, value: Dictionary) -> void:
	if kind == "profile":
		start.present_profile(value)
		notifications_screen.present_profile(value)
	if kind == "archive":
		displayed_report = value.duplicate(true)
		api.remember_report(value)
		report_screen.present_archive(api.saved_reports)
	_progress_screen(kind).present(value)
