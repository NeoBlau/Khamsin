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


func before_each() -> void:
	if not World.is_ready or Rng.world_seed != SEED:
		Rng.set_world_seed(SEED)
		World.build_now(SEED)
	GameState.new_game(SEED)
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

	truck = VehicleBody.new()
	truck.config_id = &"tabuk_6t"
	truck.player_controlled = false
	truck.surface_provider = World.surface_at
	world.add_child(truck)

	var ground := field.height(x, z)
	truck.global_transform = Transform3D(
		Basis(Vector3.UP, heading), Vector3(x, ground + 1.4, z)
	)
	truck.set_pressure_all(pressure)
	manager.build_immediate(truck.global_position)
	await simulate(2.5)


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
	check_greater(
		truck.global_transform.basis.y.dot(Vector3.UP), 0.9, "на дюне машина стоит ровно"
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
	await _spawn(1200.0, -1100.0, 0.0, 2.8)
	var start_hard := truck.global_position
	await _drive(12.0, 0.9)
	var hard := Vector2(
		truck.global_position.x - start_hard.x, truck.global_position.z - start_hard.z
	).length()
	after_each()

	await _spawn(1200.0, -1100.0, 0.0, 1.0)
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
