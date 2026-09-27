extends ScrollContainer
signal refresh_requested
signal replay_requested

func set_status(message: String, failed: bool = false, loading: bool = false) -> void:
	%Status.text = message
	%Status.theme_type_variation = &"Error" if failed else &"Small"
	%Refresh.text = "Повторить загрузку" if failed else "Обновить"
	%Refresh.disabled = loading

func _on_refresh() -> void:
	refresh_requested.emit()

func _on_replay() -> void:
	replay_requested.emit()
