class_name Widgets
extends RefCounted
## Мелкие конструкторы для интерфейса.
##
## Интерфейс собирается кодом, а не сценами: экранов много, они однотипные, и
## поддерживать три десятка .tscn-файлов с ручной расстановкой якорей заметно
## дороже, чем два десятка функций.


static func label(text: String, size: int = 15, colour: Color = UiTheme.INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", colour)
	return node


static func title(text: String) -> Label:
	return label(text, 24, UiTheme.SAND)


static func caption(text: String) -> Label:
	return label(text, 12, UiTheme.INK_DIM)


static func wrapped(text: String, size: int = 14, colour: Color = UiTheme.INK_DIM) -> Label:
	var node := label(text, size, colour)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func button(text: String, action: Callable = Callable()) -> Button:
	var node := Button.new()
	node.text = text
	if action.is_valid():
		node.pressed.connect(action)
	return node


static func separator() -> HSeparator:
	var line := HSeparator.new()
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.LINE
	box.content_margin_top = 1.0
	line.add_theme_stylebox_override("separator", box)
	return line


static func spacer(minimum: float = 0.0) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0.0, minimum)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return node


static func row(children: Array[Control], separation: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	for child: Control in children:
		box.add_child(child)
	return box


static func column(children: Array[Control], separation: int = 6) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	for child: Control in children:
		box.add_child(child)
	return box


## Строка «название — значение», выровненная по краям панели.
static func field(name: String, value: String, colour: Color = UiTheme.INK) -> HBoxContainer:
	var left := label(name, 14, UiTheme.INK_DIM)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := label(value, 14, colour)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return row([left, right])


## Горизонтальная полоска-индикатор с подписью.
static func gauge(name: String, fraction: float, text: String = "") -> VBoxContainer:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(fraction, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, 6.0)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.18, 0.17, 0.16, 0.9)
	background.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.gauge_colour(fraction)
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	var header := field(name, text if text != "" else "%d%%" % roundi(fraction * 100.0))
	return column([header, bar], 3)


static func panel(child: Control, colour: Color = UiTheme.PANEL) -> PanelContainer:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel", UiTheme.panel_box(colour))
	container.add_child(child)
	return container


## Полноэкранная затемняющая подложка для модальных окон.
static func dim() -> ColorRect:
	var rect := ColorRect.new()
	# Затемнение ровно настолько, чтобы окно читалось, а мир за ним оставался
	# виден: игрок должен понимать, где стоит машина, не закрывая экран.
	rect.color = Color(0.02, 0.02, 0.03, 0.5)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return rect


static func scroll(child: Control) -> ScrollContainer:
	var container := ScrollContainer.new()
	container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(child)
	return container
