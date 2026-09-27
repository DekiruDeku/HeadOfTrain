extends Button
signal request_selected(request_id: String)
var request_id := ""
const Crew = preload("res://scripts/crew_state.gd")

func bind_request(data: Dictionary, elapsed: float = 0.0, selected: bool = false) -> void:
	request_id = data.id
	text = ("▶ " if selected else "") + data.text
	text += "\nВагон " + str(data.get("carriage_id", "")).trim_prefix("carriage-") + " · " + Crew.priority_text(data)
	text += "\n" + Crew.symbol(data) + " " + Crew.status_text(data)
	if data.has("reaction_remaining") and data.state != "completed":
		text += "\n" + Crew.reaction(data, elapsed)
	elif data.state == "completed":
		text += "\nВыбрать · посмотреть последствия" if data.has("reaction_remaining") else "\nОткрыть сохранённый разбор"
	accessibility_name = text

func _on_pressed() -> void:
	request_selected.emit(request_id)
