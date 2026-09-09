class_name TerrainManager
extends Node3D
## Потоковая подгрузка ландшафта вокруг игрока.
##
## Чанк живёт в трёх состояниях: нужен — считается в рабочем потоке — стоит в
## сцене. Пересчёт запускается и при въезде в новую область, и при смене LOD,
## поэтому у ближних чанков сетка мельче, а дальние обходятся сотней
## треугольников.
##
## Коллизия строится только у ближнего кольца. Дальше она не нужна никому:
## машина туда не дотянется, а рейкасты подвески всё равно короче ста метров.

signal initial_chunks_ready()

## Сколько чанков одновременно считается в рабочих потоках.
const MAX_JOBS := 6
## Сколько готовых чанков разрешено собрать за один кадр. Ограничение против
## рывка при въезде в новую область.
const MAX_APPLY_PER_FRAME := 2
## Сколько разрешено собрать, когда под игроком ещё нет твёрдой земли.
const MAX_APPLY_URGENT := 8

@export var target: Node3D

var field: TerrainField
var chunk_size: float = 256.0
var view_radius: int = 8
var collision_radius: int = 1
var collision_cell: float = 2.0
var lod_divisions: Array[int] = [128, 64, 32, 16, 8, 8]
var lod_distances: Array[float] = [400.0, 800.0, 1600.0, 2800.0, 4400.0]

var _chunks: Dictionary[Vector2i, TerrainChunk] = {}
var _queue: Array[Vector2i] = []
var _jobs: Dictionary[Vector2i, int] = {}
var _results: Dictionary[Vector2i, Dictionary] = {}
var _mutex: Mutex = Mutex.new()
var _material: ShaderMaterial
var _rock_mesh: ArrayMesh
var _last_centre: Vector2i = Vector2i(9999, 9999)
var _announced_ready: bool = false


func _ready() -> void:
	chunk_size = Config.chunk_size
	view_radius = Config.chunk_view_radius
	collision_radius = Config.chunk_collision_radius
	collision_cell = Config.collision_cell
	lod_divisions = Config.lod_divisions.duplicate()
	lod_distances = Config.lod_distances.duplicate()
	_material = _make_material()
	_rock_mesh = MeshFactory.rock(Rng.world_seed)
	set_process(false)


func begin(terrain_field: TerrainField, follow: Node3D) -> void:
	field = terrain_field
	target = follow
	_last_centre = Vector2i(9999, 9999)
	_announced_ready = false
	set_process(true)


func _make_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	material.set_shader_parameter("wind_direction", Vector2(
		cos(Config.dune_wind_angle), sin(Config.dune_wind_angle)
	))
	return material


func material() -> ShaderMaterial:
	return _material


func _process(_delta: float) -> void:
	if field == null or target == null:
		return
	var centre := world_to_chunk(target.global_position)
	if centre != _last_centre:
		_last_centre = centre
		_refresh_desired(centre)
	_collect_results()
	_start_jobs()
	_check_ready(centre)


func world_to_chunk(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / chunk_size), floori(point.z / chunk_size))


func chunk_origin(coordinate: Vector2i) -> Vector2:
	return Vector2(float(coordinate.x) * chunk_size, float(coordinate.y) * chunk_size)


func chunk_centre(coordinate: Vector2i) -> Vector2:
	return chunk_origin(coordinate) + Vector2.ONE * chunk_size * 0.5


## Уровень детализации по расстоянию до игрока.
func lod_for(coordinate: Vector2i, from: Vector3) -> int:
	var distance := chunk_centre(coordinate).distance_to(Vector2(from.x, from.z))
	for level: int in lod_distances.size():
		if distance < lod_distances[level]:
			return level
	return lod_divisions.size() - 1


func _refresh_desired(centre: Vector2i) -> void:
	if target == null or not is_instance_valid(target):
		return
	var wanted: Dictionary[Vector2i, bool] = {}
	var from := target.global_position
	for j: int in range(centre.y - view_radius, centre.y + view_radius + 1):
		for i: int in range(centre.x - view_radius, centre.x + view_radius + 1):
			var coordinate := Vector2i(i, j)
			wanted[coordinate] = true
			var desired_lod := lod_for(coordinate, from)
			var existing: TerrainChunk = _chunks.get(coordinate)
			var needs_collision := _needs_collision(coordinate, centre)
			if existing != null and existing.lod == desired_lod and existing.has_collision == needs_collision:
				continue
			if _jobs.has(coordinate) or _queue.has(coordinate):
				continue
			_queue.append(coordinate)

	for coordinate: Vector2i in _chunks.keys():
		if wanted.has(coordinate):
			continue
		var chunk: TerrainChunk = _chunks[coordinate]
		_chunks.erase(coordinate)
		chunk.queue_free()
	_queue = _queue.filter(func(c: Vector2i) -> bool: return wanted.has(c))
	# Сначала то, что держит машину, потом всё остальное по близости.
	_queue.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var a_urgent := _needs_collision(a, centre)
			var b_urgent := _needs_collision(b, centre)
			if a_urgent != b_urgent:
				return a_urgent
			var flat := Vector2(from.x, from.z)
			return chunk_centre(a).distance_squared_to(flat) < chunk_centre(b).distance_squared_to(flat)
	)


func _needs_collision(coordinate: Vector2i, centre: Vector2i) -> bool:
	var delta := coordinate - centre
	return absi(delta.x) <= collision_radius and absi(delta.y) <= collision_radius


func _start_jobs() -> void:
	while _jobs.size() < MAX_JOBS and not _queue.is_empty():
		var coordinate: Vector2i = _queue.pop_front()
		var level := lod_for(coordinate, target.global_position)
		# Считать сетку коллизии заново, если она уже стоит, не нужно: рельеф
		# не меняется, а замена формы под машиной роняет её сквозь землю.
		var existing: TerrainChunk = _chunks.get(coordinate)
		var has_collision := existing != null and existing.has_collision
		var wants_collision := _needs_collision(coordinate, _last_centre) and not has_collision
		var task := WorkerThreadPool.add_task(
			_build_job.bind(coordinate, level, wants_collision), true, "Ландшафт %s" % coordinate
		)
		_jobs[coordinate] = task


## Тело задачи. Работает в рабочем потоке: только чистые вычисления и одна
## запись в общий словарь под мьютексом.
func _build_job(coordinate: Vector2i, level: int, wants_collision: bool) -> void:
	var divisions: int = lod_divisions[clampi(level, 0, lod_divisions.size() - 1)]
	var data := TerrainChunk.build_data(
		field,
		chunk_origin(coordinate),
		chunk_size,
		divisions,
		collision_cell,
		wants_collision,
		level <= 2,
		Rng.world_seed
	)
	data["lod"] = level
	_mutex.lock()
	_results[coordinate] = data
	_mutex.unlock()


func _collect_results() -> void:
	var applied := 0
	# Пока под игроком нет коллизии, бюджет на сборку не действует. На низком
	# кадре два чанка в кадр — это секунды, за которые машина успевает доехать
	# до края построенной земли и провалиться.
	var budget := MAX_APPLY_PER_FRAME if _collision_ready() else MAX_APPLY_URGENT
	for coordinate: Vector2i in _jobs.keys():
		if applied >= budget:
			break
		var task: int = _jobs[coordinate]
		if not WorkerThreadPool.is_task_completed(task):
			continue
		WorkerThreadPool.wait_for_task_completion(task)
		_jobs.erase(coordinate)
		_mutex.lock()
		var data: Dictionary = _results.get(coordinate, {})
		_results.erase(coordinate)
		_mutex.unlock()
		if data.is_empty():
			continue
		_install(coordinate, data)
		applied += 1


func _install(coordinate: Vector2i, data: Dictionary) -> void:
	var chunk: TerrainChunk = _chunks.get(coordinate)
	if chunk == null:
		chunk = TerrainChunk.new()
		chunk.setup(coordinate, chunk_size, _material)
		add_child(chunk)
		_chunks[coordinate] = chunk
	chunk.apply_data(
		data, int(data["lod"]), collision_cell, _rock_mesh, _needs_collision(coordinate, _last_centre)
	)


## Есть ли твёрдая земля во всём ближнем кольце вокруг игрока.
func _collision_ready() -> bool:
	if target == null or not is_instance_valid(target):
		return true
	var centre := world_to_chunk(target.global_position)
	for j: int in range(centre.y - collision_radius, centre.y + collision_radius + 1):
		for i: int in range(centre.x - collision_radius, centre.x + collision_radius + 1):
			var chunk: TerrainChunk = _chunks.get(Vector2i(i, j))
			if chunk == null or not chunk.has_collision:
				return false
	return true


## Готов ли ландшафт под игроком. По этому сигналу мир снимает загрузочный экран
## и отпускает машину — иначе она успевает провалиться сквозь несобранную землю.
func _check_ready(_centre: Vector2i) -> void:
	if _announced_ready or not _collision_ready():
		return
	_announced_ready = true
	initial_chunks_ready.emit()


func loaded_chunk_count() -> int:
	return _chunks.size()


func pending_count() -> int:
	return _queue.size() + _jobs.size()


## Строит ближнее кольцо синхронно. Нужно на старте: ждать кадры ради того,
## чтобы под машиной появилась земля, — плохая идея, она успеет улететь вниз.
##
## Центральный чанк собирается на полной детализации, соседние — на следующей.
## Разница видна в паре сотен метров от машины и живёт полсекунды, пока потоки
## не подтянут их до нормы, зато загрузка вместо четырёх секунд занимает две.
func build_immediate(around: Vector3) -> void:
	var centre := world_to_chunk(around)
	_last_centre = centre
	for j: int in range(centre.y - collision_radius, centre.y + collision_radius + 1):
		for i: int in range(centre.x - collision_radius, centre.x + collision_radius + 1):
			var coordinate := Vector2i(i, j)
			var level := 0 if coordinate == centre else mini(1, lod_divisions.size() - 1)
			var data := TerrainChunk.build_data(
				field, chunk_origin(coordinate), chunk_size, lod_divisions[level],
				collision_cell, true, coordinate == centre, Rng.world_seed
			)
			data["lod"] = level
			_install(coordinate, data)
	_announced_ready = true
	# Соседей сразу ставим в очередь на полную детализацию.
	_refresh_desired(centre)
