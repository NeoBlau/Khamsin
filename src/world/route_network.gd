class_name RouteNetwork
extends RefCounted
## Накатанные пути между посёлками.
##
## Дороги не рисуются вручную и не кладутся поверх рельефа. Они прокладываются
## поиском пути по стоимости, где дорого лезть в крутой склон и дорого идти по
## рыхлому песку. Получается ровно то, что делают живые водители в пустыне:
## петля в обход дюнной гряды вместо прямой линии.
##
## После прокладки трасса сглаживает под собой землю и меняет покрытие на
## накатку — поэтому по ней действительно быстрее, а не только красивее.

class Route extends RefCounted:
	var id: StringName = &""
	var from_id: StringName = &""
	var to_id: StringName = &""
	## Точки в мировых координатах, высота уже сглажена вдоль трассы.
	var points: PackedVector3Array = PackedVector3Array()
	var length: float = 0.0


## Сторона ячейки поиска пути, метры. Мельче — красивее петли и дольше сборка.
const ROUTING_CELL := 128.0
## Сторона ячейки пространственного индекса отрезков, метры.
const INDEX_CELL := 256.0
## За сколько метров от края дороги рельеф возвращается к естественному.
const BLEND_MARGIN := 26.0

var half_width: float = 11.0
var routes: Array[Route] = []

var _segments: PackedVector3Array = PackedVector3Array()
var _index: Dictionary[Vector2i, PackedInt32Array] = {}
var _extent: float = 10000.0
var _built: bool = false


func is_built() -> bool:
	return _built


## Строит сеть. `settlements` — массив словарей с ключами id и position (Vector2).
func build(field: TerrainField, settlements: Array[Dictionary], neighbours: int = 3) -> void:
	_extent = field.world_extent
	half_width = Config.track_half_width
	routes.clear()
	_segments.clear()
	_index.clear()
	if settlements.size() < 2:
		_built = true
		return

	var grid := _build_cost_grid(field)
	var pairs := _pick_connections(settlements, neighbours)
	for pair: Vector2i in pairs:
		var from: Dictionary = settlements[pair.x]
		var to: Dictionary = settlements[pair.y]
		var route := _solve(grid, field, from, to)
		if route != null:
			routes.append(route)
	_build_index()
	_built = true


func _cell_count() -> int:
	return int(ceil(_extent * 2.0 / ROUTING_CELL))


func _world_to_cell(point: Vector2) -> Vector2i:
	var count := _cell_count()
	return Vector2i(
		clampi(int(floor((point.x + _extent) / ROUTING_CELL)), 0, count - 1),
		clampi(int(floor((point.y + _extent) / ROUTING_CELL)), 0, count - 1)
	)


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		float(cell.x) * ROUTING_CELL - _extent + ROUTING_CELL * 0.5,
		float(cell.y) * ROUTING_CELL - _extent + ROUTING_CELL * 0.5
	)


## Стоимость проезда по каждой ячейке. Именно здесь живёт весь «характер»
## дорожной сети: поменяйте веса — и трассы поедут по другим местам.
func _build_cost_grid(field: TerrainField) -> AStarGrid2D:
	var count := _cell_count()
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, count, count)
	grid.cell_size = Vector2(ROUTING_CELL, ROUTING_CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()

	for j: int in count:
		for i: int in count:
			var world := _cell_to_world(Vector2i(i, j))
			if not field.is_inside(world.x, world.y):
				grid.set_point_solid(Vector2i(i, j), true)
				continue
			var steepness := field.slope(world.x, world.y, ROUTING_CELL * 0.5)
			var softness := field.dune_mask(world.x, world.y)
			# Крутизна дороже мягкости: объехать дюну по песку дешевле, чем
			# лезть на неё в лоб. Квадрат — чтобы пологое почти ничего не стоило.
			var weight := 1.0 + steepness * steepness * 9.0 + softness * 2.2
			grid.set_point_weight_scale(Vector2i(i, j), clampf(weight, 1.0, 60.0))
	return grid


## Кого с кем соединять: каждый посёлок со своими ближайшими соседями. Даёт
## связный граф без единой развязки посреди пустыни.
func _pick_connections(settlements: Array[Dictionary], neighbours: int) -> Array[Vector2i]:
	var pairs: Array[Vector2i] = []
	var seen: Dictionary[int, bool] = {}
	for i: int in settlements.size():
		var origin: Vector2 = settlements[i]["position"]
		var order: Array[int] = []
		for j: int in settlements.size():
			if j != i:
				order.append(j)
		order.sort_custom(
			func(a: int, b: int) -> bool:
				var pa: Vector2 = settlements[a]["position"]
				var pb: Vector2 = settlements[b]["position"]
				return origin.distance_squared_to(pa) < origin.distance_squared_to(pb)
		)
		for k: int in mini(neighbours, order.size()):
			var j: int = order[k]
			var key := mini(i, j) * 1000 + maxi(i, j)
			if seen.has(key):
				continue
			seen[key] = true
			pairs.append(Vector2i(i, j))
	return pairs


func _solve(
	grid: AStarGrid2D, field: TerrainField, from: Dictionary, to: Dictionary
) -> Route:
	var start := _world_to_cell(from["position"])
	var goal := _world_to_cell(to["position"])
	if start == goal:
		return null
	# Конечные точки обязаны быть проходимы, даже если стоят у самой границы.
	grid.set_point_solid(start, false)
	grid.set_point_solid(goal, false)
	var cells := grid.get_id_path(start, goal)
	if cells.size() < 2:
		return null

	var raw := PackedVector2Array()
	raw.append(from["position"])
	for index: int in range(1, cells.size() - 1):
		raw.append(_cell_to_world(cells[index]))
	raw.append(to["position"])

	var smoothed := _chaikin(_chaikin(raw))
	var route := Route.new()
	route.from_id = from["id"]
	route.to_id = to["id"]
	route.id = StringName("%s-%s" % [route.from_id, route.to_id])
	route.points = _lift(field, smoothed, float(from["height"]), float(to["height"]))
	route.length = _polyline_length(route.points)
	return route


## Сглаживание Чайкина: срезает углы сетки, оставляя форму маршрута. Два
## прохода превращают лесенку ячеек в кривую, по которой можно ехать.
func _chaikin(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var out := PackedVector2Array()
	out.append(points[0])
	for i: int in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	out.append(points[points.size() - 1])
	return out


## Поднимает плоскую линию на рельеф и продольно сглаживает высоту: дорога
## должна быть грейдированной, а не повторять каждую кочку.
func _lift(
	field: TerrainField, points: PackedVector2Array, from_height: float, to_height: float
) -> PackedVector3Array:
	var heights := PackedFloat32Array()
	heights.resize(points.size())
	for i: int in points.size():
		heights[i] = field.base_height(points[i].x, points[i].y)

	var smoothed := heights.duplicate()
	for _pass: int in 3:
		for i: int in range(1, smoothed.size() - 1):
			smoothed[i] = (heights[i - 1] + heights[i] * 2.0 + heights[i + 1]) * 0.25
		heights = smoothed.duplicate()

	# Концы притягиваем к площадкам посёлков: иначе трасса приходит на своей
	# высоте, площадка стоит на своей, и на въезде получается ступенька.
	var tail := maxi(2, points.size() / 6)
	for i: int in mini(tail, smoothed.size()):
		var w := 1.0 - float(i) / float(tail)
		smoothed[i] = lerpf(smoothed[i], from_height, w * w)
	for i: int in mini(tail, smoothed.size()):
		var index := smoothed.size() - 1 - i
		var w := 1.0 - float(i) / float(tail)
		smoothed[index] = lerpf(smoothed[index], to_height, w * w)

	var out := PackedVector3Array()
	out.resize(points.size())
	for i: int in points.size():
		out[i] = Vector3(points[i].x, smoothed[i], points[i].y)
	return out


static func _polyline_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for i: int in range(points.size() - 1):
		total += Vector2(points[i].x, points[i].z).distance_to(
			Vector2(points[i + 1].x, points[i + 1].z)
		)
	return total


# --- Пространственный индекс ------------------------------------------------

func _build_index() -> void:
	for route: Route in routes:
		for i: int in range(route.points.size() - 1):
			var a := route.points[i]
			var b := route.points[i + 1]
			var base := _segments.size()
			_segments.append(a)
			_segments.append(b)
			_register(base / 2, a, b)


func _register(segment_id: int, a: Vector3, b: Vector3) -> void:
	var reach := half_width + BLEND_MARGIN
	var min_x := minf(a.x, b.x) - reach
	var max_x := maxf(a.x, b.x) + reach
	var min_z := minf(a.z, b.z) - reach
	var max_z := maxf(a.z, b.z) + reach
	var from := Vector2i(floori(min_x / INDEX_CELL), floori(min_z / INDEX_CELL))
	var to := Vector2i(floori(max_x / INDEX_CELL), floori(max_z / INDEX_CELL))
	for j: int in range(from.y, to.y + 1):
		for i: int in range(from.x, to.x + 1):
			var key := Vector2i(i, j)
			var bucket: PackedInt32Array = _index.get(key, PackedInt32Array())
			bucket.append(segment_id)
			_index[key] = bucket


## Ближайшая точка сети: возвращает [расстояние по горизонтали, высота дороги].
## Если рядом ничего нет, расстояние равно INF.
func nearest(x: float, z: float) -> Vector2:
	var key := Vector2i(floori(x / INDEX_CELL), floori(z / INDEX_CELL))
	var bucket: PackedInt32Array = _index.get(key, PackedInt32Array())
	if bucket.is_empty():
		return Vector2(INF, 0.0)
	var point := Vector2(x, z)
	var best_distance := INF
	var best_height := 0.0
	for segment_id: int in bucket:
		var a := _segments[segment_id * 2]
		var b := _segments[segment_id * 2 + 1]
		var flat_a := Vector2(a.x, a.z)
		var flat_b := Vector2(b.x, b.z)
		var delta := flat_b - flat_a
		var length_squared := delta.length_squared()
		var t := 0.0 if length_squared < 1e-6 else clampf(
			(point - flat_a).dot(delta) / length_squared, 0.0, 1.0
		)
		var closest := flat_a + delta * t
		var distance := point.distance_to(closest)
		if distance < best_distance:
			best_distance = distance
			best_height = lerpf(a.y, b.y, t)
	return Vector2(best_distance, best_height)


func on_track(x: float, z: float) -> bool:
	return nearest(x, z).x <= half_width


## Притягивает рельеф к полотну дороги. Внутри полосы — ровно высота трассы,
## дальше плавный переход к естественной земле.
func flatten(x: float, z: float, natural_height: float) -> float:
	var hit := nearest(x, z)
	if not is_finite(hit.x) or hit.x > half_width + BLEND_MARGIN:
		return natural_height
	var blend := smoothstep(half_width, half_width + BLEND_MARGIN, hit.x)
	return lerpf(hit.y, natural_height, blend)


## Маршрут между двумя посёлками, если он есть.
func find_route(from_id: StringName, to_id: StringName) -> Route:
	for route: Route in routes:
		if (route.from_id == from_id and route.to_id == to_id) or (
			route.from_id == to_id and route.to_id == from_id
		):
			return route
	return null


## Длина пути по сети между посёлками. Если прямого маршрута нет, считается
## сумма по цепочке через промежуточные точки, найденной поиском в ширину.
func path_length(from_id: StringName, to_id: StringName) -> float:
	var direct := find_route(from_id, to_id)
	if direct != null:
		return direct.length
	var graph: Dictionary[StringName, Array] = {}
	for route: Route in routes:
		graph.get_or_add(route.from_id, []).append([route.to_id, route.length])
		graph.get_or_add(route.to_id, []).append([route.from_id, route.length])
	var best: Dictionary[StringName, float] = {from_id: 0.0}
	var queue: Array[StringName] = [from_id]
	while not queue.is_empty():
		var current: StringName = queue.pop_front()
		for edge: Array in graph.get(current, []):
			var next: StringName = edge[0]
			var distance: float = best[current] + float(edge[1])
			if distance < float(best.get(next, INF)):
				best[next] = distance
				queue.append(next)
	return float(best.get(to_id, 0.0))
