extends Button

signal request_selected(request_id: String)
var request_id := ""

func bind_request(data: Dictionary) -> void:
	request_id = data["id"]
	text = "%s  %s\n%s · %s" % [data["number"], data["title"], data["place"], data["state"]]
	accessibility_name = text

func _on_pressed() -> void:
	request_selected.emit(request_id)
