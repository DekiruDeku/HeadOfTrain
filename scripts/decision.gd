extends ScrollContainer
signal choice_selected(incident_id: String, action_id: String)
signal cancelled
const Text = preload("res://scripts/server_text.gd")
const Crew = preload("res://scripts/crew_state.gd")
var state: Dictionary = {}
var received_at := 0
var incident_id := ""
var options: Array = []
@onready var choices: Array = [%Choice1, %Choice2, %Choice3]

func present(value: Dictionary, incident: Dictionary, reset_scroll: bool = true) -> void:
	state = value
	received_at = Time.get_ticks_msec()
	incident_id = incident.id
	%Title.text = str(incident.get("title", "Решение по обращению"))
	for carriage in state.carriages:
		if carriage.id == incident.carriage_id:
			%Place.text = carriage.name + " · " + Crew.priority_text(incident)
			if incident.marker_id == "luggage-marker":
				%Place.text += " · " + Text.condition(state.conditions)
	%Description.text = incident.text + "\n\n" + state.dialog.text
	%Note.text = "Выберите действие. Условия, последствия и оценки определяет сервер."
	if Crew.enabled(state):
		%Note.text = "Рейс приостановлен сервером: движение, сервис и сроки реакции не идут. Критическое решение отсчитывается отдельно."
		if state.has("fixture_label"):
			%Note.text = "ФИКСТУРЫ А3 · " + state.fixture_label + "\n" + %Note.text
	options = state.dialog.options
	var entry := Crew.latest_entry(state, incident_id)
	%LastEffect.visible = not entry.is_empty()
	if not entry.is_empty():
		%LastEffect.text = "Подтверждено сервером\n" + entry.selected_text + "\n" + Text.effects(entry.effects) + "\n" + entry.explanation
	for i in choices.size():
		choices[i].visible = i < options.size()
		if i < options.size():
			var option: Dictionary = options[i]
			choices[i].text = "%s. %s" % [i + 1, option.text]
			if not option.available:
				choices[i].text += "\nНедоступно: " + str(option.get("unavailable_reason") if option.get("unavailable_reason") != null else "условия не выполнены")
	set_locked(false)
	if reset_scroll:
		scroll_vertical = 0
	_update_timer()

func _process(_delta: float) -> void:
	_update_timer()

func _update_timer() -> void:
	%CriticalTimer.visible = Crew.enabled(state)
	if not Crew.enabled(state):
		return
	var time_left: Variant = state.get("dialog", {}).get("critical_remaining")
	if time_left == null:
		%CriticalTimer.text = "ПАУЗА РЕЙСА · Этот узел без критического таймера"
	else:
		var elapsed := minf(float(Time.get_ticks_msec() - received_at) / 1000.0, 2.0)
		%CriticalTimer.text = "ПАУЗА РЕЙСА · На критическое решение: " + Crew.seconds(float(time_left) - elapsed)
		if float(time_left) - elapsed <= 0:
			%CriticalTimer.text += "\nОжидаем исход от сервера"

func set_locked(locked: bool) -> void:
	for i in choices.size():
		choices[i].disabled = locked or i >= options.size() or not options[i].available

func _on_choice(index: int) -> void:
	if index >= options.size() or choices[index].disabled:
		return
	set_locked(true)
	choice_selected.emit(incident_id, options[index].id)

func _on_cancel() -> void:
	cancelled.emit()
