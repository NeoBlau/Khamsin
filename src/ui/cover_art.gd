class_name CoverArt
extends Control
## Обложка игры. Рисуется в коде, как и всё остальное.
##
## Нужна дважды: как заставка при запуске и как фон главного меню. Рисовать её
## один раз и использовать дважды — не экономия, а решение: игрок видит один
## и тот же кадр, и меню воспринимается частью обложки, а не поверх неё.
##
## Это не случайный набор линий. Гребни дюн складываются из синусов с разными
## периодами — тот же приём, что и в настоящем рельефе игры; солнце садится
## ровно на дальний гребень; ближний план темнее и холоднее дальнего, потому
## что до него не доходит рассеянный свет. Из-за этого плоская картинка
## читается глубокой.

## Слои дюн от дальнего к ближнему.
const LAYERS := 5
## Высота горизонта в долях кадра.
const HORIZON := 0.56

@export var seed_value: int = 20260907
@export var hour: float = 17.6
@export var show_vehicle: bool = true
@export var show_title: bool = false

var _sky: Gradient
var _time: float = 0.0


func _ready() -> void:
	# Именно and_offsets: обычный set_anchors_preset переносит якоря, но
	# сбрасывает отступы в минимальный размер, и контрол остаётся нулевым.
	# Рисование при этом честно вызывается и честно ничего не рисует.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky = _build_sky()
	set_process(true)


func _process(delta: float) -> void:
	# Очень медленное дыхание марева. Заметить его нельзя, а без него кадр
	# выглядит остановившимся.
	_time += delta
	queue_redraw()


func _build_sky() -> Gradient:
	var gradient := Gradient.new()
	var evening := clampf((hour - 15.0) / 4.0, 0.0, 1.0)
	gradient.set_color(0, Color(0.30, 0.36, 0.52).lerp(Color(0.18, 0.16, 0.28), evening))
	gradient.set_color(1, Color(0.78, 0.74, 0.62).lerp(Color(0.92, 0.58, 0.28), evening))
	gradient.add_point(0.62, Color(0.72, 0.68, 0.60).lerp(Color(0.88, 0.50, 0.26), evening))
	return gradient


func _draw() -> void:
	var box := size
	if box.x < 2.0 or box.y < 2.0:
		return
	_draw_sky(box)
	_draw_sun(box)
	_draw_dunes(box)
	if show_vehicle:
		_draw_vehicle(box)
	_draw_haze(box)
	if show_title:
		_draw_title(box)


func _draw_sky(box: Vector2) -> void:
	var horizon := box.y * HORIZON
	var bands := 48
	for i: int in bands:
		var t := float(i) / float(bands - 1)
		var colour := _sky.sample(t)
		draw_rect(
			Rect2(0.0, t * horizon, box.x, horizon / float(bands) + 1.0), colour, true
		)
	# Ниже горизонта — песок, освещённый тем же небом.
	draw_rect(Rect2(0.0, horizon, box.x, box.y - horizon), _sky.sample(1.0).darkened(0.08), true)


func _draw_sun(box: Vector2) -> void:
	var horizon := box.y * HORIZON
	var centre := Vector2(box.x * 0.68, horizon - box.y * 0.015)
	var radius := box.y * 0.052
	# Ореол: несколько полупрозрачных кругов вместо честного свечения.
	for i: int in 7:
		var t := float(i) / 6.0
		draw_circle(
			centre, radius * (1.0 + t * 5.5),
			Color(1.0, 0.72, 0.38, 0.05 * (1.0 - t))
		)
	draw_circle(centre, radius, Color(1.0, 0.88, 0.62))


## Гребень дюны: сумма синусов разного периода. Один синус читается как волна,
## три — как песок.
func _ridge(x: float, layer: int, width: float) -> float:
	var phase := float(layer) * 2.7 + float(seed_value % 97) * 0.13
	var u := x / width
	var value := sin(u * TAU * (0.7 + float(layer) * 0.35) + phase) * 0.55
	value += sin(u * TAU * (1.9 + float(layer) * 0.6) + phase * 1.7) * 0.28
	value += sin(u * TAU * (4.3 + float(layer) * 0.9) + phase * 0.6) * 0.12
	return value


func _draw_dunes(box: Vector2) -> void:
	var horizon := box.y * HORIZON
	for layer: int in LAYERS:
		var depth := float(layer) / float(LAYERS - 1)
		# Дальние слои выше по кадру, ниже по контрасту и холоднее.
		var base := horizon + depth * depth * (box.y - horizon) * 0.92
		var amplitude := box.y * (0.012 + depth * 0.075)
		var warm := Color(0.86, 0.76, 0.56)
		var cool := Color(0.32, 0.26, 0.24)
		var colour := warm.lerp(cool, depth * 0.88)
		# Наветренный склон длинный, подветренный короткий: гребень смещён.
		var points := PackedVector2Array()
		var steps := 96
		for i: int in steps + 1:
			var x := float(i) / float(steps) * box.x
			var height := _ridge(x, layer, box.x)
			# Асимметрия: положительную часть растягиваем, отрицательную режем.
			height = height * (1.0 if height < 0.0 else 0.72)
			points.append(Vector2(x, base - height * amplitude))
		points.append(Vector2(box.x, box.y))
		points.append(Vector2(0.0, box.y))
		draw_colored_polygon(points, colour)
		# Светлая кромка по гребню: она и создаёт ощущение объёма.
		var crest := PackedVector2Array()
		for i: int in steps + 1:
			crest.append(points[i])
		draw_polyline(crest, colour.lightened(0.22), maxf(box.y * 0.002, 1.0), true)


## Силуэт машины на ближнем гребне. Он маленький — весь смысл обложки в том,
## что пустыня больше.
func _draw_vehicle(box: Vector2) -> void:
	var horizon := box.y * HORIZON
	var layer := LAYERS - 2
	var depth := float(layer) / float(LAYERS - 1)
	var base := horizon + depth * depth * (box.y - horizon) * 0.92
	var amplitude := box.y * (0.012 + depth * 0.075)
	var x := box.x * 0.30
	var height := _ridge(x, layer, box.x)
	height = height * (1.0 if height < 0.0 else 0.72)
	var ground := base - height * amplitude

	var unit := box.y * 0.021
	var colour := Color(0.12, 0.10, 0.11)
	var body := PackedVector2Array([
		Vector2(x - unit * 2.6, ground),
		Vector2(x - unit * 2.6, ground - unit * 0.9),
		Vector2(x - unit * 1.5, ground - unit * 0.9),
		Vector2(x - unit * 1.2, ground - unit * 1.8),
		Vector2(x + unit * 0.1, ground - unit * 1.8),
		Vector2(x + unit * 0.3, ground - unit * 0.95),
		Vector2(x + unit * 2.7, ground - unit * 0.95),
		Vector2(x + unit * 2.7, ground),
	])
	draw_colored_polygon(body, colour)
	for offset: float in [-1.8, 1.9]:
		draw_circle(Vector2(x + unit * offset, ground), unit * 0.52, colour)
	# Пыль за машиной: она и говорит, что машина едет, а не стоит.
	for i: int in 9:
		var t := float(i) / 8.0
		draw_circle(
			Vector2(x + unit * (2.9 + t * 7.0), ground - unit * (0.2 + t * 0.9)),
			unit * (0.5 + t * 1.5),
			Color(0.72, 0.64, 0.50, 0.24 * (1.0 - t))
		)


## Марево над горизонтом: горизонтальные полосы, медленно плывущие.
func _draw_haze(box: Vector2) -> void:
	var horizon := box.y * HORIZON
	for i: int in 7:
		var t := float(i) / 6.0
		var y := horizon - box.y * 0.02 + t * box.y * 0.05
		var drift := sin(_time * 0.12 + t * 3.1) * box.x * 0.01
		draw_rect(
			Rect2(drift - box.x * 0.02, y, box.x * 1.04, box.y * 0.006),
			Color(1.0, 0.92, 0.78, 0.05 * (1.0 - t)),
			true
		)


func _draw_title(box: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var title_size := int(box.y * 0.14)
	var title := "ХАМСИН"
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	var at := Vector2((box.x - width) * 0.5, box.y * 0.30)
	# Тень под буквами: на светлом небе без неё заголовок не читается.
	draw_string(font, at + Vector2(0.0, box.y * 0.004), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(0.18, 0.12, 0.08, 0.5))
	draw_string(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size,
		Color(0.96, 0.90, 0.76))

	var subtitle := "курьерский рейс через эрг"
	var sub_size := int(box.y * 0.032)
	var sub_width := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
	draw_string(font, Vector2((box.x - sub_width) * 0.5, box.y * 0.30 + box.y * 0.055),
		subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, Color(0.88, 0.78, 0.58, 0.92))
