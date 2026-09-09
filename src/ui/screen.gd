class_name Screen
extends Control
## Общий каркас оверлейных экранов.
##
## Затемнение, панель, заголовок, кнопка закрытия и обработка Escape — всё
## одинаковое для биржи, карты, гаража и журнала. Наследник переопределяет
## `build_body` и получает готовое окно.

var payload: Dictionary = {}
var body: VBoxContainer
var header: HBoxContainer

var _title: Label


func setup(data: Dictionary) -> void:
	payload = data


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	add_child(Widgets.dim())

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.panel_box())
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.custom_minimum_size = window_size()
	frame.pivot_offset = window_size() * 0.5
	frame.position = -window_size() * 0.5
	add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)

	_title = Widgets.title(window_title())
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header = Widgets.row([_title, Widgets.button("Закрыть  Esc", close)])
	column.add_child(header)
	column.add_child(Widgets.separator())

	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	build_body()


## Переопределяется наследником.
func window_title() -> String:
	return "Экран"


func window_size() -> Vector2:
	return Vector2(880.0, 560.0)


func build_body() -> void:
	pass


func set_window_title(text: String) -> void:
	if _title != null:
		_title.text = text


func close() -> void:
	SceneRouter.close(StringName(name))


func rebuild() -> void:
	for child: Node in body.get_children():
		child.queue_free()
		body.remove_child(child)
	build_body()
