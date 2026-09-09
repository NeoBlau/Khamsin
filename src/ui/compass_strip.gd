class_name CompassStrip
extends Control
## Лента компаса поверх экрана.
##
## Полоса, а не круглая шкала: в кабине смотрят вперёд, и курс удобнее читать
## там же, где дорога. Метка цели едет по той же ленте, поэтому «где север» и
## «куда ехать» — один взгляд, а не два.

## Сколько градусов помещается в ленту.
const SPAN := 140.0
const CARDINALS: Dictionary[int, String] = {
	0: "С", 45: "СВ", 90: "В", 135: "ЮВ", 180: "Ю", 225: "ЮЗ", 270: "З", 315: "СЗ",
}

## Курс машины в градусах, 0 — север, растёт по часовой.
var heading: float = 0.0
## Цели: массив словарей {bearing: float, colour: Color, label: String}.
var markers: Array[Dictionary] = []


func _ready() -> void:
	custom_minimum_size = Vector2(460.0, 40.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(new_heading: float, new_markers: Array[Dictionary]) -> void:
	heading = new_heading
	markers = new_markers
	queue_redraw()


func _draw() -> void:
	var width := size.x
	var middle := width * 0.5
	var pixels_per_degree := width / SPAN

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.06, 0.07, 0.55))
	draw_line(Vector2(0.0, size.y - 1.0), Vector2(width, size.y - 1.0), UiTheme.LINE, 1.0)

	var font := ThemeDB.fallback_font
	for degrees: int in range(0, 360, 15):
		var offset := _offset(float(degrees), pixels_per_degree, middle)
		if offset < -20.0 or offset > width + 20.0:
			continue
		var is_cardinal := CARDINALS.has(degrees)
		var height := 12.0 if is_cardinal else 6.0
		var colour := UiTheme.INK if is_cardinal else UiTheme.INK_FAINT
		draw_line(Vector2(offset, size.y - height), Vector2(offset, size.y), colour, 1.0)
		if is_cardinal:
			var text: String = CARDINALS[degrees]
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			draw_string(
				font, Vector2(offset - text_size.x * 0.5, size.y - 15.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.INK
			)

	for marker: Dictionary in markers:
		var offset := _offset(float(marker.get("bearing", 0.0)), pixels_per_degree, middle)
		var colour: Color = marker.get("colour", UiTheme.SAND)
		# Цель за пределами ленты прижимается к краю и остаётся видимой — иначе
		# игрок теряет её ровно тогда, когда она нужнее всего.
		var clamped := clampf(offset, 6.0, width - 6.0)
		var tip := Vector2(clamped, 20.0)
		draw_colored_polygon(
			PackedVector2Array([tip, tip + Vector2(-5.0, -7.0), tip + Vector2(5.0, -7.0)]), colour
		)
		var text := String(marker.get("label", ""))
		if text != "":
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			draw_string(
				font, Vector2(clampf(clamped - text_size.x * 0.5, 2.0, width - text_size.x - 2.0), 11.0),
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, colour
			)

	draw_line(Vector2(middle, 0.0), Vector2(middle, size.y), UiTheme.SAND, 1.0)


## Положение азимута на ленте в пикселях.
func _offset(bearing: float, pixels_per_degree: float, middle: float) -> float:
	var delta := wrapf(bearing - heading, -180.0, 180.0)
	return middle + delta * pixels_per_degree
