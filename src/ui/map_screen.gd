extends Screen
## Карта мира: посёлки, трассы, машина, адреса активных заказов.
##
## Показывается только то, что игрок уже видел. Незнакомый посёлок не
## обозначен — про него можно узнать из разговора или наткнуться самому.

class MapView extends Control:
	var vehicle: VehicleBody
	var hovered: Settlement = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(820.0, 470.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var closest: Settlement = null
			var best := 22.0
			for settlement: Settlement in World.settlements:
				if not GameState.known_settlements.has(settlement.id):
					continue
				var distance := _to_screen(settlement.position).distance_to(
					(event as InputEventMouseMotion).position
				)
				if distance < best:
					best = distance
					closest = settlement
			if closest != hovered:
				hovered = closest
				queue_redraw()

	## Мировые координаты в координаты виджета, с сохранением пропорций.
	func _to_screen(point: Vector2) -> Vector2:
		var extent := Config.world_extent
		var scale := minf(size.x, size.y) / (extent * 2.0)
		var centre := size * 0.5
		return centre + point * scale

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.115, 0.095, 0.97))
		_draw_grid()
		if World.field == null:
			return

		var font := ThemeDB.fallback_font
		for route: RouteNetwork.Route in World.routes.routes:
			if not _route_known(route):
				continue
			var points := PackedVector2Array()
			for i: int in range(0, route.points.size(), 3):
				points.append(_to_screen(Vector2(route.points[i].x, route.points[i].z)))
			if points.size() >= 2:
				draw_polyline(points, Color(0.66, 0.57, 0.40, 0.95), 2.0)

		var destinations: Dictionary[StringName, bool] = {}
		for contract: Contract in GameState.active_contracts():
			destinations[contract.destination_id] = true

		for settlement: Settlement in World.settlements:
			if not GameState.known_settlements.has(settlement.id):
				continue
			var point := _to_screen(settlement.position)
			var is_target := destinations.has(settlement.id)
			var colour := UiTheme.SAND if is_target else UiTheme.INK_DIM
			var radius := 7.0 if settlement.kind == Settlement.Kind.CITY else 5.0
			draw_circle(point, radius, colour)
			if is_target:
				draw_arc(point, radius + 5.0, 0.0, TAU, 24, UiTheme.SAND, 1.5)
			draw_string(
				font, point + Vector2(9.0, 4.0), settlement.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, colour
			)

		if vehicle != null and is_instance_valid(vehicle):
			var here := _to_screen(Vector2(vehicle.global_position.x, vehicle.global_position.z))
			var forward := -vehicle.global_transform.basis.z
			var angle := atan2(forward.x, forward.z)
			var nose := here + Vector2(sin(angle), cos(angle)) * 9.0
			var left := here + Vector2(sin(angle + 2.4), cos(angle + 2.4)) * 7.0
			var right := here + Vector2(sin(angle - 2.4), cos(angle - 2.4)) * 7.0
			draw_colored_polygon(PackedVector2Array([nose, left, right]), UiTheme.INK)

		if hovered != null:
			var box := _to_screen(hovered.position) + Vector2(12.0, 10.0)
			var text := "%s · %s" % [hovered.display_name, hovered.kind_name()]
			draw_string(font, box, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.INK)
			draw_string(
				font, box + Vector2(0.0, 16.0), _services(hovered),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.INK_FAINT
			)

	## Километровая сетка и масштабная линейка: без них карта не даёт понять,
	## десять там километров до посёлка или сто.
	func _draw_grid() -> void:
		var extent := Config.world_extent
		var scale := minf(size.x, size.y) / (extent * 2.0)
		var step := 2000.0
		var colour := Color(0.24, 0.21, 0.17, 0.7)
		var world := -extent
		while world <= extent:
			var screen := _to_screen(Vector2(world, world))
			draw_line(Vector2(screen.x, 0.0), Vector2(screen.x, size.y), colour, 1.0)
			draw_line(Vector2(0.0, screen.y), Vector2(size.x, screen.y), colour, 1.0)
			world += step

		var bar := 5000.0 * scale
		var origin := Vector2(16.0, size.y - 22.0)
		draw_line(origin, origin + Vector2(bar, 0.0), UiTheme.INK_DIM, 2.0)
		draw_line(origin + Vector2(0.0, -4.0), origin + Vector2(0.0, 4.0), UiTheme.INK_DIM, 2.0)
		draw_line(
			origin + Vector2(bar, -4.0), origin + Vector2(bar, 4.0), UiTheme.INK_DIM, 2.0
		)
		draw_string(
			ThemeDB.fallback_font, origin + Vector2(bar + 8.0, 4.0), "5 км",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.INK_DIM
		)


	func _route_known(route: RouteNetwork.Route) -> bool:
		return (
			GameState.known_settlements.has(route.from_id)
			and GameState.known_settlements.has(route.to_id)
		)

	func _services(settlement: Settlement) -> String:
		var names := PackedStringArray()
		for service: StringName in settlement.services:
			match service:
				&"fuel": names.append("топливо")
				&"repair": names.append("ремонт")
				&"market": names.append("рынок")
				&"bunk": names.append("ночлег")
				&"clinic": names.append("врач")
				&"guild": names.append("гильдия")
		return " · ".join(names) if not names.is_empty() else "услуг нет"


func window_title() -> String:
	return "Карта"


func window_size() -> Vector2:
	return Vector2(900.0, 620.0)


func build_body() -> void:
	var view := MapView.new()
	view.vehicle = _find_vehicle()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(view)

	var legend := PackedStringArray()
	legend.append("Известно посёлков: %d из %d" % [
		GameState.known_settlements.size(), World.settlements.size()
	])
	legend.append("Активных заказов: %d" % GameState.active_contracts().size())
	if view.vehicle != null:
		legend.append("Одометр: %s" % Settings.format_distance(view.vehicle.odometer))
	body.add_child(Widgets.label("   ".join(legend), 13, UiTheme.INK_DIM))
	body.add_child(
		Widgets.caption("Мир на карте не останавливается: M закрывает её, не выходя из движения.")
	)


func _find_vehicle() -> VehicleBody:
	var nodes := get_tree().get_nodes_in_group(&"player_vehicle")
	return nodes[0] if not nodes.is_empty() else null
