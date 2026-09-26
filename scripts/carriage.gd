extends AspectRatioContainer

signal request_selected(request_id: String)

func _on_request_selected(request_id: String) -> void:
	request_selected.emit(request_id)
