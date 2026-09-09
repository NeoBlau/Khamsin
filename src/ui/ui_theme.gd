class_name UiTheme
extends RefCounted
## Оформление интерфейса, собранное кодом.
##
## Шрифт берётся встроенный: в проекте нет ни одного импортированного ассета, и
## интерфейс не должен быть исключением. Когда появится нормальная гарнитура,
## меняется одна функция, а не тридцать сцен.
##
## Палитра пустынная и намеренно тусклая: приборы читаются поверх песка, а
## песок на экране очень светлый, поэтому панели тёмные и полупрозрачные.

const INK := Color(0.93, 0.90, 0.83)
const INK_DIM := Color(0.72, 0.68, 0.60)
const INK_FAINT := Color(0.52, 0.49, 0.44)
const SAND := Color(0.85, 0.70, 0.38)
const DANGER := Color(0.88, 0.36, 0.28)
const WARNING := Color(0.92, 0.68, 0.24)
const GOOD := Color(0.52, 0.78, 0.46)
const PANEL := Color(0.07, 0.065, 0.075, 0.90)
const PANEL_SOFT := Color(0.11, 0.10, 0.11, 0.86)
const LINE := Color(0.28, 0.25, 0.22, 0.9)

static var _theme: Theme = null


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 15

	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())

	t.set_stylebox("normal", "Button", button_box(Color(0.16, 0.15, 0.15, 0.92)))
	t.set_stylebox("hover", "Button", button_box(Color(0.24, 0.22, 0.19, 0.96)))
	t.set_stylebox("pressed", "Button", button_box(Color(0.32, 0.27, 0.17, 0.98)))
	t.set_stylebox("disabled", "Button", button_box(Color(0.12, 0.12, 0.12, 0.6)))
	t.set_stylebox("focus", "Button", focus_box())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", INK_FAINT)
	t.set_font_size("font_size", "Button", 15)

	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "RichTextLabel", INK)
	t.set_stylebox("normal", "LineEdit", button_box(Color(0.10, 0.10, 0.11, 0.95)))
	t.set_color("font_color", "LineEdit", INK)

	t.set_stylebox("tab_selected", "TabContainer", button_box(Color(0.24, 0.21, 0.16, 0.98)))
	t.set_stylebox("tab_unselected", "TabContainer", button_box(Color(0.12, 0.12, 0.12, 0.85)))
	t.set_stylebox("panel", "TabContainer", panel_box())

	t.set_stylebox("slider", "HSlider", line_box(Color(0.22, 0.20, 0.18)))
	t.set_stylebox("grabber_area", "HSlider", line_box(SAND))
	_theme = t
	return t


static func panel_box(colour: Color = PANEL) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.border_color = LINE
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	return box


static func button_box(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(2)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	box.border_color = LINE
	box.set_border_width_all(1)
	return box


static func focus_box() -> StyleBoxFlat:
	var box := button_box(Color(0.20, 0.18, 0.14, 0.95))
	box.border_color = SAND
	box.set_border_width_all(1)
	return box


static func line_box(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(2)
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	return box


## Цвет для доли 0..1, где единица — хорошо. Одинаковый по всему интерфейсу:
## топливо, целостность груза, износ резины читаются одним взглядом.
static func gauge_colour(fraction: float) -> Color:
	if fraction > 0.5:
		return GOOD.lerp(SAND, clampf((1.0 - fraction) * 2.0, 0.0, 1.0))
	return WARNING.lerp(DANGER, clampf((0.5 - fraction) * 2.0, 0.0, 1.0))
