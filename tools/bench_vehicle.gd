extends Node
## Стенд телеметрии.
##
## Гоняет машину без окна и печатает то, что обычно узнают, катаясь час:
## разгон, тормозной путь, максимальную скорость, разницу покрытий, выигрыш от
## спуска колёс и предельный уклон. Рядом кладёт CSV полного заезда — по нему
## строится кривая разгона, если нужно смотреть глазами.
##
## Запуск:
##   godot --headless --path games/khamsin res://tools/bench_vehicle.tscn
##
## Это не тест: он ничего не утверждает, он измеряет. Пороговые проверки живут
## в tests/, а сюда ходят, когда меняют настройки машины и хотят понять, что
## именно изменилось.

const STEP := 1.0 / 120.0
const OUT_DIR := "res://telemetry"
## Печатать состояние машины перед каждым замером. Диагностика самого стенда.
const VERBOSE := false

var _world: Node3D
var _ground: StaticBody3D
var _truck: VehicleBody
var _report: PackedStringArray = PackedStringArray()


func _ready() -> void:
	Catalog.ensure_loaded()
	GameState.new_game(20260907)
	var config := Catalog.vehicle(&"tabuk_6t")
	var power := config.peak_power()

	_line("Машина: %s" % config.display_name)
	_line("  снаряжённая масса %.0f кг, груз до %.0f кг" % [config.mass, config.cargo_mass_limit])
	_line("  момент %.0f Н·м, мощность %.0f кВт (%.0f л.с.) при %.0f об/мин"
		% [config.peak_torque(), power.x, power.x * 1.36, power.y])
	_line("  бак %.0f л, передач %d, понижающая %.2f"
		% [config.fuel_capacity, config.top_gear(), config.transfer_low])
	_line("")

	await _build_rig()
	await _acceleration_table()
	await _braking_table()
	await _pressure_table()
	await _gradient_table()
	await _record_run()

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var file := FileAccess.open("%s/report.txt" % OUT_DIR, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_report))
		file.close()
	get_tree().quit()


## Печатаем сразу, а не в конце: прогон занимает минуты, и молчащий стенд
## неотличим от зависшего.
func _line(text: String) -> void:
	_report.append(text)
	print(text)


# --- Стенд -----------------------------------------------------------------
#
# Основание и машина создаются один раз, а между замерами машина возвращается
# на старт. Пересоздавать сцену на каждый прогон соблазнительно, но два стенда,
# на кадр наложившиеся друг на друга, дают неповторяемые числа — и ищешь потом
# ошибку в физике, которой там нет.

var _surface_id: StringName = &"gravel"


## Собирает основание и машину. Полоса длинная во все стороны: замеры идут
## подряд, машина не возвращается на старт, а просто едет дальше по прямой.
##
## Никаких телепортов между заездами. Переставлять живое тело физики — верный
## способ получить неповторяемые числа: узел и сервер физики расходятся на кадр,
## колёса успевают посчитать силы в старом месте, и машина остаётся стоять с
## ревущим двигателем. Проще не переставлять.
func _build_rig(slope: float = 0.0) -> void:
	_world = Node3D.new()
	add_child(_world)

	_ground = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000.0, 6.0, 24000.0)
	shape.shape = box
	_ground.add_child(shape)
	_ground.rotation = Vector3(slope, 0.0, 0.0)
	_ground.position = Vector3(0.0, -3.0, 0.0)
	var material := PhysicsMaterial.new()
	material.friction = 1.0
	_ground.physics_material_override = material
	_world.add_child(_ground)

	_truck = VehicleBody.new()
	_truck.config_id = &"tabuk_6t"
	_truck.player_controlled = false
	_truck.surface_provider = func(_p: Vector3) -> Surface: return Surface.get_by_id(_surface_id)
	_world.add_child(_truck)
	_truck.global_transform = Transform3D(
		Basis(Vector3.RIGHT, slope), Vector3(0.0, 1.4, 0.0)
	)
	await _wait(2.5)


## Готовит машину к следующему замеру, не сдвигая её с места.
func _reset(surface_id: StringName, pressure: float) -> void:
	_surface_id = surface_id
	_truck.input.reset()
	_truck.linear_velocity = Vector3.ZERO
	_truck.angular_velocity = Vector3.ZERO
	_truck.set_pressure_all(pressure)
	_truck.fuel = _truck.config.fuel_capacity
	_truck.engine_health = 1.0
	_truck.suspension_health = 1.0
	_truck.body_health = 1.0
	_truck.drivetrain.running = true
	_truck.drivetrain.coolant_temp = Drivetrain.AMBIENT_TEMP
	_truck.drivetrain.low_range = false
	_truck.drivetrain.diff_locked = false
	_truck.drivetrain.force_gear(0)
	for wheel: VehicleWheel in _truck.wheels:
		wheel.wear = 0.0
		wheel.angular_velocity = 0.0
	await _wait(2.0)
	if VERBOSE:
		var grounded := 0
		var load := 0.0
		for wheel: VehicleWheel in _truck.wheels:
			if wheel.grounded:
				grounded += 1
			load += wheel.load
		print("    [сброс] y=%.2f z=%.0f колёс на земле %d, реакция %.0f Н, масса %.0f, %s"
			% [
				_truck.global_position.y, _truck.global_position.z, grounded, load,
				_truck.mass, _surface_id
			])


## Полная пересборка стенда. Нужна только там, где меняется уклон основания.
func _rebuild(slope: float) -> void:
	_teardown()
	for _i: int in 3:
		await get_tree().process_frame
	await _build_rig(slope)


func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	_world = null
	_truck = null


func _wait(seconds: float) -> void:
	for _i: int in roundi(seconds / STEP):
		await get_tree().physics_frame


## Разгон до целевой скорости. Возвращает секунды или -1, если не доехал.
func _time_to(target: float, limit: float) -> float:
	_truck.input.throttle = 1.0
	var elapsed := 0.0
	while elapsed < limit:
		await get_tree().physics_frame
		elapsed += STEP
		if _truck.forward_speed >= target:
			_truck.input.throttle = 0.0
			return elapsed
	_truck.input.throttle = 0.0
	return -1.0


func _acceleration_table() -> void:
	_line("Разгон, секунды (пусто / с полным кузовом)")
	_line("  покрытие        0-30 км/ч   0-60 км/ч   макс. скорость")
	for surface_id: StringName in [&"asphalt", &"track", &"gravel", &"sand_firm", &"sand_soft"]:
		var surface := Surface.get_by_id(surface_id)
		await _reset(surface_id, 2.2)
		var to_thirty := await _time_to(30.0 / 3.6, 25.0)
		await _reset(surface_id, 2.2)
		var to_sixty := await _time_to(60.0 / 3.6, 45.0)
		await _reset(surface_id, 2.2)
		_truck.input.throttle = 1.0
		var start := _truck.global_position
		await _wait(28.0)
		var top := _truck.forward_speed * 3.6
		var travelled := start.distance_to(_truck.global_position)
		_truck.input.throttle = 0.0
		_line("  %-14s  %9s   %9s   %6.0f км/ч (передача %d, %.0f об/мин)"
			% [
				surface.display_name,
				"—" if to_thirty < 0.0 else "%.1f" % to_thirty,
				"—" if to_sixty < 0.0 else "%.1f" % to_sixty,
				top,
				_truck.drivetrain.gear,
				_truck.drivetrain.rpm(),
			])
		_line("                  за 28 с пройдено %.0f м, вертикальность %.2f"
			% [travelled, _truck.global_transform.basis.y.dot(Vector3.UP)])
	_line("")


func _braking_table() -> void:
	_line("Тормозной путь с 60 км/ч, метры")
	for surface_id: StringName in [&"asphalt", &"track", &"gravel", &"sand_firm"]:
		var surface := Surface.get_by_id(surface_id)
		await _reset(surface_id, 2.2)
		var reached := await _time_to(60.0 / 3.6, 45.0)
		if reached < 0.0:
			_line("  %-14s  до шестидесяти не разгоняется" % surface.display_name)
			continue
		var start := _truck.global_position
		var entry := _truck.forward_speed
		_truck.input.brake = 1.0
		var elapsed := 0.0
		while _truck.forward_speed > 0.4 and elapsed < 20.0:
			await get_tree().physics_frame
			elapsed += STEP
		_truck.input.brake = 0.0
		var distance := start.distance_to(_truck.global_position)
		var deceleration := entry * entry / (2.0 * maxf(distance, 0.01)) / Config.gravity
		_line("  %-14s  %6.1f м   среднее замедление %.2f g"
			% [surface.display_name, distance, deceleration])
	_line("")


func _pressure_table() -> void:
	_line("Рыхлый песок: сколько метров пройдено за 20 с полного газа")
	for pressure: float in [2.8, 2.4, 1.8, 1.4, 1.0]:
		await _reset(&"sand_soft", pressure)
		var start := _truck.global_position
		_truck.input.throttle = 1.0
		await _wait(20.0)
		_truck.input.throttle = 0.0
		var distance := start.distance_to(_truck.global_position)
		var sink := 0.0
		for wheel: VehicleWheel in _truck.wheels:
			sink = maxf(sink, wheel.sinkage)
		_line("  %.1f бар   %6.0f м   скорость %5.1f км/ч   просадка колеса %.0f см"
			% [pressure, distance, _truck.forward_speed * 3.6, sink * 100.0])
	_line("")


func _gradient_table() -> void:
	_line("Предельный подъём (двадцать секунд на въезд), градусы")
	for surface_id: StringName in [&"gravel", &"sand_firm", &"sand_soft"]:
		var surface := Surface.get_by_id(surface_id)
		var best := 0.0
		for degrees: int in [5, 10, 15, 20, 25, 30]:
			await _rebuild(deg_to_rad(-float(degrees)))
			await _reset(surface_id, 1.6)
			var start := _truck.global_position
			_truck.drivetrain.low_range = true
			_truck.drivetrain.diff_locked = true
			_truck.input.throttle = 1.0
			await _wait(12.0)
			_truck.input.throttle = 0.0
			# Считаем взятым подъём, на который машина заехала хотя бы на
			# десять метров: буксовать на месте она умеет на любом уклоне.
			if start.distance_to(_truck.global_position) > 6.0:
				best = float(degrees)
			else:
				break
		_line("  %-14s  до %.0f°" % [surface.display_name, best])
	_line("")


## Полный заезд с записью в CSV: по нему видно форму кривой, а не только точки.
func _record_run() -> void:
	await _reset(&"gravel", 2.2)
	Telemetry.begin(PackedStringArray([
		"time", "speed_kmh", "rpm", "gear", "throttle", "slip_front", "load_front", "fuel_l"
	]))
	_truck.input.throttle = 1.0
	var elapsed := 0.0
	while elapsed < 30.0:
		await get_tree().physics_frame
		elapsed += STEP
		Telemetry.push(PackedFloat32Array([
			elapsed,
			_truck.forward_speed * 3.6,
			_truck.drivetrain.rpm(),
			float(_truck.drivetrain.gear),
			_truck.command.throttle,
			_truck.wheels[0].slip_ratio,
			_truck.wheels[0].load,
			_truck.fuel,
		]))
	_truck.input.throttle = 0.0
	Telemetry.stop()

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/acceleration_gravel.csv" % OUT_DIR
	if Telemetry.write_csv(path):
		_line("Полный заезд записан: %s (%d отсчётов)" % [path, Telemetry.sample_count()])
	var speeds := Telemetry.column("speed_kmh")
	if not speeds.is_empty():
		_line("  максимум на тридцати секундах: %.0f км/ч" % speeds[speeds.size() - 1])
