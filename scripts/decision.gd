extends ScrollContainer

signal choice_selected(request_id: String, choice_index: int)
signal cancelled
var request_id := ""
@onready var choices: Array = [%Choice1, %Choice2, %Choice3]

func present(data: Dictionary) -> void:
	request_id = data["id"]
	%Title.text = data["title"]
	%Place.text = "Вагон 01 · %s · демонстрация" % data["place"]
	%Description.text = data["description"]
	var options: Array = data["choices"]
	for i in choices.size():
		choices[i].visible = i < options.size()
		choices[i].disabled = false
		if i < options.size():
			choices[i].text = "%s. %s" % [i + 1, options[i]]
	scroll_vertical = 0

func _on_choice(index: int) -> void:
	for choice in choices:
		choice.disabled = true
	choice_selected.emit(request_id, index)

func _on_cancel() -> void:
	cancelled.emit()
