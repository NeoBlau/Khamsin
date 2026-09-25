class_name Grime
extends Node
## Грязь на машине: пыль, соль и верблюжьи плевки.
##
## Пыль — не косметика. Она ложится на кузов от пройденного пути и от бури, на
## стекло садится быстрее, чем на борта, и через грязное стекло хуже видно.
## Отмывается водой где угодно.
##
## Плевок верблюда — отдельная история. Он не смывается водой: верблюжья
## слюна густая, липкая и въедается в краску. Отмыть её можно только в оазисе
## Дяди Вали — там для этого есть и вода, и щётки, и человек, который делал
## это уже много раз и перестал удивляться.
##
## Обе величины живут в сейве и переживают перезапуск: приехать на мойку —
## это задача, а не кнопка в меню.

signal changed()

## Пыли на километр по самому пыльному покрытию.
const DUST_PER_KM := 0.055
## Прибавка за час в песчаной буре.
const DUST_PER_STORM_HOUR := 0.62
## Во сколько раз быстрее пылится стекло: оно вертикальное и его ничем не
## обдувает, кроме набегающего потока.
const GLASS_FACTOR := 1.8
## Сколько видимости съедает полностью грязное стекло.
const GLASS_VISIBILITY_COST := 0.42

var dust: float = 0.0
var glass_dust: float = 0.0
## Плевки: каждый — своя точка на кузове, чтобы их было видно и можно было
## пересчитать.
var splats: Array[Dictionary] = []

var vehicle: VehicleBody
var weather: Weather

var _panels: Array[MeshInstance3D] = []
var _base_colours: Array[Color] = []
var _base_roughness: PackedFloat32Array = PackedFloat32Array()
var _splat_nodes: Array[Node3D] = []
var _last_odometer: float = 0.0
var _applied_dust: float = -1.0


func _ready() -> void:
	name = "Grime"
	set_process(true)


func attach(target: VehicleBody, sky_weather: Weather) -> void:
	vehicle = target
	weather = sky_weather
	_panels = target.paint.duplicate()
	_base_colours.clear()
	_base_roughness.resize(0)
	for panel: MeshInstance3D in _panels:
		var material := panel.material_override as StandardMaterial3D
		_base_colours.append(material.albedo_color if material != null else Color.WHITE)
		_base_roughness.append(material.roughness if material != null else 0.7)
	_last_odometer = target.odometer
	_restore()
	_refresh()


# --- Состояние --------------------------------------------------------------


func serialize() -> Dictionary:
	return {"dust": dust, "glass": glass_dust, "splats": splats.duplicate(true)}


func deserialize(data: Dictionary) -> void:
	dust = clampf(float(data.get("dust", 0.0)), 0.0, 1.0)
	glass_dust = clampf(float(data.get("glass", 0.0)), 0.0, 1.0)
	splats.clear()
	for entry: Variant in data.get("splats", []):
		if entry is Dictionary:
			splats.append(entry as Dictionary)
	_refresh()


func _restore() -> void:
	deserialize(GameState.vehicle.get("grime", {}))


func _store() -> void:
	GameState.vehicle["grime"] = serialize()


# --- Накопление -------------------------------------------------------------


func _process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var driven := maxf(vehicle.odometer - _last_odometer, 0.0)
	_last_odometer = vehicle.odometer
	if driven > 0.0:
		var surface := World.surface_at(vehicle.global_position)
		var dustiness := surface.dust if surface != null else 0.4
		var added := driven / 1000.0 * DUST_PER_KM * dustiness
		dust = clampf(dust + added, 0.0, 1.0)
		glass_dust = clampf(glass_dust + added * GLASS_FACTOR, 0.0, 1.0)
	if weather != null and weather.dust > 0.3:
		# Буря пылит и на стоянке: стоять в ней ничем не лучше, чем ехать.
		var hours := delta / Config.seconds_per_game_hour
		var storm := hours * DUST_PER_STORM_HOUR * weather.dust
		dust = clampf(dust + storm, 0.0, 1.0)
		glass_dust = clampf(glass_dust + storm * GLASS_FACTOR, 0.0, 1.0)
	if absf(dust - _applied_dust) > 0.01:
		_refresh()


## Плевок прилетел. Точка задаётся в местных координатах кузова, чтобы клякса
## осталась там же после перезагрузки.
func add_splat(local_point: Vector3, size: float = 1.0) -> void:
	splats.append({
		"x": local_point.x,
		"y": local_point.y,
		"z": local_point.z,
		"size": clampf(size, 0.4, 2.0),
	})
	# На стекло тоже попадает, и это самое неприятное.
	glass_dust = clampf(glass_dust + 0.12, 0.0, 1.0)
	_refresh()
	EventBus.notify("Верблюд плюнул в машину", &"warning")


func splat_count() -> int:
	return splats.size()


# --- Мойка ------------------------------------------------------------------


## Моет машину. `full` — с щётками и горячей водой, как в оазисе: снимает и
## плевки тоже. Возвращает, что именно удалось отмыть.
func wash(full: bool) -> Dictionary:
	var removed_dust := dust
	var removed_splats := 0
	dust = 0.0
	glass_dust = 0.0
	if full:
		removed_splats = splats.size()
		splats.clear()
	_refresh()
	_store()
	return {"dust": removed_dust, "splats": removed_splats, "left": splats.size()}


## Насколько грязное стекло. Ноль — чистое.
func windscreen_grime() -> float:
	# Плевки на стекле мешают сильнее пыли: пыль размазана ровно, а клякса
	# закрывает кусок обзора целиком.
	return clampf(glass_dust + float(splats.size()) * 0.05, 0.0, 1.0)


## Потеря видимости из-за грязного стекла, в долях.
func visibility_penalty() -> float:
	return windscreen_grime() * GLASS_VISIBILITY_COST


# --- Вид --------------------------------------------------------------------


func _refresh() -> void:
	_applied_dust = dust
	_paint_panels()
	_rebuild_splats()
	_store()
	changed.emit()


## Пыль не перекрашивает кузов, а выцветает его: цвет уходит к песочному,
## шероховатость растёт. Блеск пропадает первым — именно по нему глаз и
## понимает, что машина грязная.
func _paint_panels() -> void:
	var dust_colour := Color(0.76, 0.70, 0.56)
	for i: int in _panels.size():
		var panel := _panels[i]
		if not is_instance_valid(panel):
			continue
		var material := panel.material_override as StandardMaterial3D
		if material == null:
			continue
		material.albedo_color = _base_colours[i].lerp(dust_colour, dust * 0.72)
		material.roughness = clampf(_base_roughness[i] + dust * 0.28, 0.0, 1.0)


func _rebuild_splats() -> void:
	for node: Node3D in _splat_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_splat_nodes.clear()
	if vehicle == null or not is_instance_valid(vehicle):
		return
	for entry: Dictionary in splats:
		var blob := _build_splat(float(entry.get("size", 1.0)))
		blob.position = Vector3(
			float(entry.get("x", 0.0)), float(entry.get("y", 0.0)), float(entry.get("z", 0.0))
		)
		vehicle.add_child(blob)
		_splat_nodes.append(blob)


## Клякса: приплюснутый ком из нескольких капель. Одна ровная лепёшка читается
## как наклейка, несколько капель разного размера — как то, чем оно и является.
func _build_splat(size: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Splat"
	var rng := RandomNumberGenerator.new()
	rng.seed = Rng.hash_string("splat:%d:%.3f" % [splats.size(), size])
	var material := MeshFactory.standard_material(Color(0.66, 0.68, 0.52), 0.32, 0.0)
	material.albedo_color.a = 0.93
	for i: int in 4:
		var drop := MeshFactory.panel(
			Vector3(0.10, 0.02, 0.10) * size * rng.randf_range(0.6, 1.4),
			Color(0.66, 0.68, 0.52), 0.32, 0.0, 0.01
		)
		drop.position = Vector3(
			rng.randfn(0.0, 0.055) * size, rng.randfn(0.0, 0.012), rng.randfn(0.0, 0.055) * size
		)
		root.add_child(drop)
	return root
