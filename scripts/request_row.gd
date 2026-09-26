extends Button
signal request_selected(request_id: String)
var request_id := ""

func bind_request(data: Dictionary) -> void:
	request_id = data.id
	text = data.text + ("\nОткрыть сохранённый разбор" if data.state == "completed" else "\nТребуется решение · приоритет высокий")
	accessibility_name = text

func _on_pressed() -> void:
	request_selected.emit(request_id)
