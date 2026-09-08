extends Node
## Мир как данные: рельеф, поселения, дорожная сеть.
##
## Автолоад, потому что мир по-настоящему глобален — на него смотрят и биржа
## контрактов, и экран карты, и генератор чанков, и сюжет. Сцена мира при этом
## может выгружаться и загружаться сколько угодно: здесь остаются только те
## данные, которые целиком выводятся из сида.
##
## Сборка идёт в рабочем потоке: поиск маршрутов между девятью посёлками — это
## десятки тысяч обращений к рельефу, и делать их в основном потоке значит
## подвесить окно на пару секунд.

signal build_started()
signal build_finished()

var field: TerrainField
var routes: RouteNetwork
var settlements: Array[Settlement] = []
var is_ready: bool = false

var _by_id: Dictionary[StringName, Settlement] = {}
var _task_id: int = -1
var _pending_seed: int = 0

const SETTLEMENTS_PATH := "res://data/world/settlements.json"


func _ready() -> void:
	set_process(false)


## Запускает сборку мира под сид. По окончании прилетает `build_finished`.
func build_async(world_seed: int) -> void:
	if _task_id != -1:
		return
	is_ready = false
	_pending_seed = world_seed
	_load_settlements()
	build_started.emit()
	_task_id = WorkerThreadPool.add_task(_build_worker, true, "Khamsin: сборка мира")
	set_process(true)


## Синхронная сборка. Нужна тестам и стенду телеметрии, где ждать кадры незачем.
func build_now(world_seed: int) -> void:
	is_ready = false
	_pending_seed = world_seed
	_load_settlements()
	_build_worker()
	_finish()


func _process(_delta: float) -> void:
	if _task_id == -1:
		return
	if not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	set_process(false)
	_finish()


func _finish() -> void:
	is_ready = true
	for settlement: Settlement in settlements:
		if settlement.known_from_start:
			GameState.discover_settlement(settlement.id)
	build_finished.emit()


func _load_settlements() -> void:
	settlements.clear()
	_by_id.clear()
	if not FileAccess.file_exists(SETTLEMENTS_PATH):
		push_error("WorldMap: нет %s" % SETTLEMENTS_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTLEMENTS_PATH))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("WorldMap: %s — ожидался массив" % SETTLEMENTS_PATH)
		return
	for entry: Variant in parsed as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var settlement := Settlement.from_dict(entry as Dictionary)
		settlements.append(settlement)
		_by_id[settlement.id] = settlement


## Тело сборки. Выполняется в рабочем потоке, поэтому здесь нельзя трогать ни
## дерево сцены, ни сигналы — только чистые вычисления.
func _build_worker() -> void:
	field = TerrainField.new(_pending_seed)
	field.apply_config()

	# Площадки посёлков считаем по чистому рельефу: дорога ещё не проложена, а
	# высота площадки нужна, чтобы дорога к ней пришла на правильном уровне.
	var descriptors: Array[Dictionary] = []
	for settlement: Settlement in settlements:
		settlement.ground_height = _plateau_height(settlement)
		descriptors.append({
			"id": settlement.id,
			"position": settlement.position,
			"radius": settlement.radius,
			"height": settlement.ground_height,
		})
	field.settlements = descriptors

	routes = RouteNetwork.new()
	routes.build(field, descriptors)
	field.routes = routes


## Высота площадки — среднее по кольцу вокруг центра. Простое взятие высоты в
## точке иногда попадает на гребень дюны, и посёлок оказывается на башне.
func _plateau_height(settlement: Settlement) -> float:
	var total := 0.0
	var samples := 0
	for i: int in 12:
		var angle := TAU * float(i) / 12.0
		var offset := Vector2(cos(angle), sin(angle)) * settlement.radius * 0.55
		total += field.base_height(
			settlement.position.x + offset.x, settlement.position.y + offset.y
		)
		samples += 1
	total += field.base_height(settlement.position.x, settlement.position.y) * 4.0
	samples += 4
	return total / float(samples)


# --- Запросы ---------------------------------------------------------------

func settlement(id: StringName) -> Settlement:
	return _by_id.get(id)


func height(x: float, z: float) -> float:
	return field.height(x, z) if field != null else 0.0


func height_at(point: Vector3) -> float:
	return height(point.x, point.z)


func surface_at(point: Vector3) -> Surface:
	if field == null:
		return Surface.default_surface()
	return field.surface_at(point.x, point.z)


## Ближайший посёлок и расстояние до него.
func nearest_settlement(point: Vector3) -> Settlement:
	var flat := Vector2(point.x, point.z)
	var best: Settlement = null
	var best_distance := INF
	for settlement: Settlement in settlements:
		var distance := flat.distance_to(settlement.position)
		if distance < best_distance:
			best_distance = distance
			best = settlement
	return best


## Посёлок, внутри которого стоит точка, иначе null.
func settlement_at(point: Vector3) -> Settlement:
	var flat := Vector2(point.x, point.z)
	for settlement: Settlement in settlements:
		if flat.distance_to(settlement.position) <= settlement.radius:
			return settlement
	return null


func known_settlements() -> Array[Settlement]:
	var out: Array[Settlement] = []
	for settlement: Settlement in settlements:
		if GameState.known_settlements.has(settlement.id):
			out.append(settlement)
	return out


## Расстояние по дорогам между посёлками. Если сети нет — по прямой.
func route_distance(from_id: StringName, to_id: StringName) -> float:
	if routes != null and routes.is_built():
		var length := routes.path_length(from_id, to_id)
		if length > 0.0:
			return length
	var a := settlement(from_id)
	var b := settlement(to_id)
	if a == null or b == null:
		return 0.0
	return a.position.distance_to(b.position)


## Свободное место рядом с посёлком, куда можно поставить машину.
func spawn_transform(id: StringName) -> Transform3D:
	var settlement := settlement(id)
	if settlement == null:
		settlement = settlements[0] if not settlements.is_empty() else null
	if settlement == null:
		return Transform3D.IDENTITY
	var offset := Vector2(cos(0.7), sin(0.7)) * settlement.radius * 0.4
	var x := settlement.position.x + offset.x
	var z := settlement.position.y + offset.y
	var facing := Vector3(-offset.x, 0.0, -offset.y).normalized()
	var basis := Basis.looking_at(facing, Vector3.UP)
	return Transform3D(basis, Vector3(x, height(x, z) + 1.2, z))
