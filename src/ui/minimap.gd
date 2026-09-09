class_name Minimap
extends Control
## Круглая мини-карта: посёлки, трассы, цель, машина.
##
## Рисуется вручную, потому что настоящая карта — это девять точек и полтора
## десятка ломаных. Держать ради этого второй Viewport с камерой сверху дороже
## по кадру и хуже читается: на виде сверху дюны сливаются в кашу.

## Сколько метров мира помещается от центра до края.
## Радиус охвата в метрах. Полтора километра — это примерно то расстояние, на
## котором ещё имеет смысл поправлять курс, и на нём почти всегда видно хотя бы
## один посёлок или трассу.
var range_metres: float = 1600.0
var vehicle_position: Vector3 = Vector3.ZERO
var vehicle_heading: float = 0.0
var target: Settlement = null


func _ready() -> void:
	custom_minimum_size = Vector2(168.0, 168.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(position: Vector3, heading: float, waypoint: Settlement) -> void:
	vehicle_position = position
	vehicle_heading = heading
	target = waypoint
	queue_redraw()


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	var centre := size * 0.5
	draw_circle(centre, radius, Color(0.06, 0.06, 0.07, 0.7))
	draw_arc(centre, radius, 0.0, TAU, 48, UiTheme.LINE, 1.0)

	if World.field == null:
		return

	# Карта поворачивается вместе с машиной: верх экрана — это направление
	# движения. Так проще соотносить её с тем, что видно в лобовое стекло.
	var rotation := deg_to_rad(-vehicle_heading)
	for route: RouteNetwork.Route in World.routes.routes:
		var points := PackedVector2Array()
		for i: int in range(0, route.points.size(), 2):
			var local := _project(route.points[i], centre, radius, rotation)
			if local == Vector2.INF:
				if points.size() >= 2:
					draw_polyline(points, Color(0.55, 0.48, 0.36, 0.75), 1.5)
				points = PackedVector2Array()
				continue
			points.append(local)
		if points.size() >= 2:
			draw_polyline(points, Color(0.55, 0.48, 0.36, 0.75), 1.5)

	var font := ThemeDB.fallback_font
	for settlement: Settlement in World.settlements:
		if not GameState.known_settlements.has(settlement.id):
			continue
		var point := _project(settlement.world_position(), centre, radius, rotation)
		if point == Vector2.INF:
			continue
		var colour := UiTheme.SAND if settlement == target else UiTheme.INK_DIM
		draw_circle(point, 4.0, colour)
		draw_string(
			font, point + Vector2(6.0, 4.0), settlement.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, colour
		)

	# Машина всегда в центре и всегда носом вверх.
	draw_colored_polygon(
		PackedVector2Array([
			centre + Vector2(0.0, -7.0), centre + Vector2(-5.0, 6.0), centre + Vector2(5.0, 6.0)
		]),
		UiTheme.INK
	)


## Мировая точка в координатах виджета. Vector2.INF — за пределами круга.
func _project(point: Vector3, centre: Vector2, radius: float, rotation: float) -> Vector2:
	var delta := Vector2(point.x - vehicle_position.x, point.z - vehicle_position.z)
	if delta.length() > range_metres:
		return Vector2.INF
	var scaled := delta / range_metres * radius
	return centre + scaled.rotated(rotation)
