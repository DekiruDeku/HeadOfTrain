extends ScrollContainer

signal back_requested

func present(title: String, choice: String) -> void:
	%Title.text = title
	%Choice.text = choice
	scroll_vertical = 0

func _on_back() -> void:
	back_requested.emit()
