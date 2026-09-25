extends TestCase
## Машина на настоящем рельефе.
##
## Отдельно от test_vehicle_dynamics, где земля — идеальная плоскость. Здесь
## проверяется то, ради чего всё затевалось: что по дюнам можно ехать. Правило
## простое — при разумном газе грузовик не должен кувыркаться сам по себе.

const SEED := 20260907
const STEP := 1.0 / 120.0

var world: Node3D
var truck: VehicleBody
var field: TerrainField
var _manager: TerrainManager


func before_each() -> void:
	if not World.is_built_for(SEED):
		Rng.set_world_seed(SEED)
		World.build_now(SEED)
	GameState.new_game(SEED)
	# Песок между тестами чистит раннер, но внутри одного теста бывает по
	# несколько заездов подряд — и второй не должен ехать по колее первого.
	World.sand.clear()
	field = World.field


func after_each() -> void:
	if world != null and is_instance_valid(world):
		world.queue_free()
	world = null
	truck = null


## Ставит машину на сгенерированный ландшафт в заданной точке.
func _spawn(x: float, z: float, heading: float, pressure: float = 2.0) -> void:
	world = Node3D.new()
	host.add_child(world)

	var manager := TerrainManager.new()
	world.add_child(manager)
	manager.field = field
	_manager = manager

	truck = VehicleBody.new()
	truck.config_id = &"tabuk_6t"
	truck.player_controlled = false
	truck.surface_provider = World.surface_at
	world.add_child(truck)

	# Машину надо ставить по склону, а не по мировой вертикали. Иначе на
	# тридцатиградусном барханe её задранный конец оказывается закопанным в
	# дюну: движок выталкивает её наружу с угловой скоростью под восемь
	# радиан в секунду, и дальше она просто катится кубарем. Так игра машину
	# нигде не ставит — это была ошибка стенда, а не физики.
	var ground := field.height(x, z)
	var normal := _terrain_normal(x, z)
	var forward := Vector3.FORWARD.rotated(Vector3.UP, heading)
	var right := forward.cross(normal).normalized()
	var basis := Basis(right, normal, right.cross(normal).normalized())
	truck.global_transform = Transform3D(basis, Vector3(x, ground + 1.1, z))
	truck.set_pressure_all(pressure)
	manager.begin(field, truck)
	manager.build_immediate(truck.global_position)
	await simulate(2.5)


## Нормаль рельефа центральными разностями. Шаг в метр: мельче — ловим рябь,
## крупнее — сглаживаем сам склон.
func _terrain_normal(x: float, z: float) -> Vector3:
	var step := 1.0
	var dx := field.height(x + step, z) - field.height(x - step, z)
	var dz := field.height(x, z + step) - field.height(x, z - step)
	return Vector3(-dx, 2.0 * step, -dz).normalized()


## Курс вверх по склону. Спущенные колёса выигрывают именно на подъёме: на
## спуске машину везёт гравитация, и давление там почти ничего не решает.
func _uphill_heading(x: float, z: float) -> float:
	var step := 2.0
	var dx := field.height(x + step, z) - field.height(x - step, z)
	var dz := field.height(x, z + step) - field.height(x, z - step)
	if absf(dx) + absf(dz) < 0.0001:
		return 0.0
	var uphill := Vector2(dx, dz).normalized()
	return atan2(-uphill.x, -uphill.y)


func _drive(seconds: float, throttle: float, steer: float = 0.0) -> Dictionary:
	truck.input.throttle = throttle
	truck.input.steer = steer
	var worst_upright := 1.0
	var top_speed := 0.0
	var steps := roundi(seconds / STEP)
	for _i: int in steps:
		await tree().physics_frame
		worst_upright = minf(worst_upright, truck.global_transform.basis.y.dot(Vector3.UP))
		top_speed = maxf(top_speed, truck.speed)
	truck.input.throttle = 0.0
	truck.input.steer = 0.0
	return {"upright": worst_upright, "top_speed": top_speed}


func test_settles_on_a_dune_without_falling_through() -> void:
	await _spawn(1200.0, -1100.0, 0.0)
	var ground := field.height(truck.global_position.x, truck.global_position.z)
	check_greater(truck.global_position.y, ground - 0.2, "машина не должна провалиться сквозь дюну")
	check(truck.global_position.y < ground + 2.0, "и не должна висеть над ней")
	# «Ровно» на дюне — это вдоль склона, а не по мировой вертикали. Склон
	# наветренной стороны доходит до тридцати трёх градусов, и машина,
	# идеально лежащая на нём, даёт с вертикалью всего 0.84. Сравнивать надо
	# с нормалью рельефа под самой машиной.
	var normal := _terrain_normal(truck.global_position.x, truck.global_position.z)
	check_greater(
		truck.global_transform.basis.y.dot(normal), 0.97, "на дюне машина лежит по склону"
	)
	check_greater(
		truck.global_transform.basis.y.dot(Vector3.UP), 0.75, "и всё же не на боку"
	)


func test_driving_across_the_dunes_does_not_flip_the_truck() -> void:
	# Четыре стартовые точки и четыре курса: если модель переворачивает машину
	# сама, хоть один из прогонов это поймает.
	var places: Array[Vector2] = [
		Vector2(1200.0, -1100.0), Vector2(-2400.0, 3100.0),
		Vector2(4600.0, -300.0), Vector2(-5200.0, -4400.0),
	]
	for i: int in places.size():
		var place: Vector2 = places[i]
		await _spawn(place.x, place.y, float(i) * PI * 0.5)
		var result := await _drive(12.0, 0.7)
		var upright: float = result["upright"]
		after_each()
		if not check(
			upright > 0.35,
			"на курсе %d машина легла набок сама (минимальная вертикальность %.2f)" % [i, upright]
		):
			return
	check(true, "по всем четырём курсам машина осталась на колёсах")


func test_the_truck_actually_moves_on_sand() -> void:
	await _spawn(1200.0, -1100.0, 0.0, 1.2)
	var start := truck.global_position
	var result := await _drive(12.0, 0.8)
	var travelled := Vector2(
		truck.global_position.x - start.x, truck.global_position.z - start.z
	).length()
	check_greater(travelled, 40.0, "за двенадцать секунд по песку надо проехать хоть сколько-то")
	check_between(float(result["top_speed"]), 4.0, 32.0, "разумная максимальная скорость, м/с")


func test_low_pressure_beats_high_pressure_on_the_same_dune() -> void:
	# Курс — вверх по склону дюны. Раньше тест ехал вниз, где машину везёт
	# гравитация, и разница между давлениями тонула в ней целиком.
	var uphill := _uphill_heading(1200.0, -1100.0)
	await _spawn(1200.0, -1100.0, uphill, 2.8)
	var start_hard := truck.global_position
	await _drive(12.0, 0.9)
	var hard := Vector2(
		truck.global_position.x - start_hard.x, truck.global_position.z - start_hard.z
	).length()
	after_each()

	await _spawn(1200.0, -1100.0, uphill, 1.0)
	var start_soft := truck.global_position
	await _drive(12.0, 0.9)
	var soft := Vector2(
		truck.global_position.x - start_soft.x, truck.global_position.z - start_soft.z
	).length()
	check_greater(
		soft, hard * 1.08,
		"на спущенных колёсах по дюне надо уехать дальше: %.0f м против %.0f м" % [soft, hard]
	)


func test_gearbox_keeps_a_low_gear_in_sand() -> void:
	await _spawn(1200.0, -1100.0, 0.0, 1.4)
	await _drive(10.0, 1.0)
	check(
		truck.drivetrain.gear <= 4,
		"в песке автомат не должен уходить на высшие передачи, стоит %d" % truck.drivetrain.gear
	)


func test_streaming_terrain_does_not_drop_the_truck() -> void:
	# Игровая сцена, в отличие от голого стенда, подгружает и пересобирает
	# чанки прямо под машиной. Проверяем, что от этого она не проваливается и
	# не переворачивается: именно так выглядел баг с пересозданием коллизии
	# при смене уровня детализации.
	await _spawn(1200.0, -1100.0, 0.4, 1.8)
	var worst_upright := 1.0
	var deepest := 0.0
	truck.input.throttle = 0.7
	for _i: int in roundi(20.0 / STEP):
		await tree().physics_frame
		worst_upright = minf(worst_upright, truck.global_transform.basis.y.dot(Vector3.UP))
		var ground := field.height(truck.global_position.x, truck.global_position.z)
		deepest = maxf(deepest, ground - truck.global_position.y)
	truck.input.throttle = 0.0

	check_greater(worst_upright, 0.35, "машина не должна лечь набок за двадцать секунд езды")
	check(
		deepest < 1.5,
		"и не должна уходить под поверхность: максимум на %.1f м ниже неё" % deepest
	)
	check_greater(float(_manager.loaded_chunk_count()), 8.0, "чанки должны подгружаться на ходу")
