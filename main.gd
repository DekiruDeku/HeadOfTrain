extends Control
## All screens and components are saved in main.tscn and nested scenes.
@onready var screens: TabContainer = %Screens
@onready var start = %StartScreen
@onready var trip = %TripScreen
@onready var decision = %Decision
@onready var debrief = %Debrief
@onready var api = $SessionAPI

func _ready() -> void:
	api.bootstrap()

func _on_api_changed() -> void:
	%ConnectionText.text = api.message + ("\n" + api.notice if not api.notice.is_empty() else "")
	%ConnectionText.theme_type_variation = &"Error" if not api.error_code.is_empty() else &"Small"
	%Retry.visible = not api.error_code.is_empty()
	%Retry.disabled = api.busy
	var locked: bool = not api.ready_for_input or api.busy
	start.set_state(api.trip, api.message, locked)
	decision.set_locked(locked)
	trip.set_locked(locked)
	debrief.set_locked(locked)

func _on_state_received(source: String) -> void:
	if api.trip.is_empty():
		screens.current_tab = 0
		return
	trip.show_trip(api.trip)
	if api.trip.status == "completed":
		# Do not show an old report while the saved report is loading.
		screens.current_tab = 1
	elif source == "action":
		debrief.present_effect(api.trip.history.back(), api.trip)
		screens.current_tab = 3
	else:
		screens.current_tab = 1
	trip.scroll_vertical = 0

func _on_report_received() -> void:
	debrief.present_report(api.report)
	screens.current_tab = 3

func _on_start() -> void:
	if not api.trip.is_empty() and api.trip.status == "in_progress":
		_on_back_to_trip()
		return
	api.start_attempt(start.selected_condition(), not api.trip.is_empty())

func _on_health() -> void:
	api.retry()

func _on_back_to_start() -> void:
	screens.current_tab = 0
	start.scroll_vertical = 0

func _on_request_selected(incident_id: String) -> void:
	if not api.ready_for_input:
		return
	if api.trip.status == "completed":
		if not api.report.is_empty():
			_on_report_received()
		return
	for incident in api.trip.incidents:
		if incident.id == incident_id:
			decision.present(api.trip, incident)
			screens.current_tab = 2
			return

func _on_choice_selected(incident_id: String, action_id: String) -> void:
	api.choose(incident_id, action_id)

func _on_back_to_trip() -> void:
	screens.current_tab = 1

func _on_continue() -> void:
	if api.trip.get("status") == "in_progress":
		_on_request_selected(api.trip.incidents[0].id)
	else:
		_on_back_to_start()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and screens.current_tab >= 2:
		_on_back_to_trip()
		get_viewport().set_input_as_handled()
