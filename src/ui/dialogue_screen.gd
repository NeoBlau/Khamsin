extends Screen
## Окно разговора.
##
## Реплика, имя говорящего, ответы. Ничего больше: разговор в этой игре —
## короткий обмен на стоянке, а не дерево на сорок узлов, и лишняя рамка вокруг
## него только мешает.

var dialogue: Dialogue

var _speaker: Label
var _text: Label
var _choices: VBoxContainer


func window_title() -> String:
	return ""


func window_size() -> Vector2:
	return Vector2(760.0, 380.0)


func build_body() -> void:
	var id := StringName(payload.get("dialogue", ""))
	dialogue = Dialogue.open(id, payload)
	if dialogue == null:
		close()
		return
	header.visible = false

	_speaker = Widgets.label("", 18, UiTheme.SAND)
	_text = Widgets.wrapped("", 17, UiTheme.INK)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)

	body.add_child(_speaker)
	body.add_child(Widgets.separator())
	body.add_child(_text)
	body.add_child(Widgets.spacer())
	body.add_child(_choices)
	_refresh()


func _refresh() -> void:
	if dialogue.is_finished():
		close()
		return
	_speaker.text = dialogue.speaker()
	_text.text = dialogue.text()

	for child: Node in _choices.get_children():
		child.queue_free()
		_choices.remove_child(child)

	var options := dialogue.choices()
	if options.is_empty():
		var next := Widgets.button("Дальше", _advance.bind(-1))
		next.size_flags_horizontal = Control.SIZE_SHRINK_END
		_choices.add_child(next)
		return
	for i: int in options.size():
		var button := Widgets.button(String(options[i].get("text", "…")), _advance.bind(i))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_choices.add_child(button)


func _advance(index: int) -> void:
	dialogue.advance(index)
	_refresh()
