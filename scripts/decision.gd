extends ScrollContainer
signal choice_selected(incident_id: String, action_id: String)
signal cancelled
const Text = preload("res://scripts/server_text.gd")
var incident_id := ""
var options: Array = []
@onready var choices: Array = [%Choice1, %Choice2, %Choice3]

func present(state: Dictionary, incident: Dictionary) -> void:
	incident_id = incident.id
	%Title.text = "Чемодан в проходе"
	%Place.text = "%s · %s" % [state.carriages[0].name, Text.condition(state.conditions)]
	%Description.text = state.dialog.text
	%Note.text = "Выберите действие. Условия, последствия и оценки определяет сервер."
	options = state.dialog.options
	for i in choices.size():
		choices[i].visible = i < options.size()
		if i < options.size():
			var option: Dictionary = options[i]
			choices[i].text = "%s. %s" % [i + 1, option.text]
			if not option.available:
				choices[i].text += "\nНедоступно: " + str(option.get("unavailable_reason", ""))
	set_locked(false)
	scroll_vertical = 0

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
