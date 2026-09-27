extends PanelContainer
signal activated(value: String)
var target := ""

func present(record: Dictionary) -> void:
	%Heading.text = str(record.get("title", ""))
	%Detail.text = str(record.get("detail", ""))
	%Footnote.text = str(record.get("footnote", ""))
	%Footnote.visible = not %Footnote.text.is_empty()
	target = str(record.get("target", ""))
	%Open.text = str(record.get("action", "Открыть"))
	%Open.visible = not target.is_empty()

func _on_open() -> void:
	activated.emit(target)
