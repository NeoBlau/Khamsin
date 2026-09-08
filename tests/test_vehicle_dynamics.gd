extends TestCase
## Машина целиком, на настоящей физике.
##
## Юнит-тесты проверяют формулы, этот — что из формул собирается грузовик:
## встаёт на подвеску на нужной высоте, разгоняется как шеститонник, тормозит
## на конечной дистанции и вязнет в песке ровно настолько, чтобы спускать
## колёса было выгодно.

var world: Node3D
var truck: VehicleBody


func after_each() -> void:
	if world != null and is_instance_valid(world):
		world.queue_free()
	world = null
	truck = null


## Ставит машину на бесконечную плоскость заданного покрытия и даёт ей осесть.
func _spawn(surface_id: StringName = &"gravel", pressure: float = 2.4) -> void:
	world = Node3D.new()
	host.add_child(world)

	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000.0, 4.0, 4000.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0.0, -2.0, 0.0)
	var material := PhysicsMaterial.new()
	material.friction = 1.0
	ground.physics_material_override = material
	world.add_child(ground)

	truck = VehicleBody.new()
	truck.config_id = &"tabuk_6t"
	truck.player_controlled = false
	truck.surface_provider = func(_point: Vector3) -> Surface: return Surface.get_by_id(surface_id)
	world.add_child(truck)
	truck.global_position = Vector3(0.0, 1.6, 0.0)
	truck.set_pressure_all(pressure)
	await simulate(2.5)


func _static_ride_height() -> float:
	# Высота начала координат кузова над землёй: полный ход минус статическое
	# сжатие пружин под собственным весом.
	var load_per_wheel := truck.mass * Config.gravity / float(truck.wheels.size())
	var compression := load_per_wheel / truck.config.spring_rate
	return truck.wheels[0].max_ray_length() - compression


func _drive(seconds: float, throttle: float, brake: float = 0.0, steer: float = 0.0) -> void:
	truck.input.throttle = throttle
	truck.input.brake = brake
	truck.input.steer = steer
	await simulate(seconds)


func test_settles_on_its_suspension() -> void:
	await _spawn()
	var expected := _static_ride_height()
	check_near(truck.global_position.y, expected, 0.07, "высота кузова после осадки, метры")
	check_greater(
		truck.global_transform.basis.y.dot(Vector3.UP), 0.995, "машина должна стоять ровно"
	)
	for wheel: VehicleWheel in truck.wheels:
		check(wheel.grounded, "все колёса должны стоять на земле")
	check(truck.linear_velocity.length() < 0.15, "осевшая машина не должна ползти")


func test_suspension_carries_the_whole_weight() -> void:
	await _spawn()
	var total := 0.0
	for wheel: VehicleWheel in truck.wheels:
		total += wheel.load
	var weight := truck.mass * Config.gravity
	check_near(total / weight, 1.0, 0.08, "сумма реакций подвески к весу машины")


func test_load_shifts_backwards_under_acceleration() -> void:
	await _spawn()
	var front_static := truck.wheels[0].load + truck.wheels[1].load
	await _drive(2.0, 1.0)
	var front_moving := truck.wheels[0].load + truck.wheels[1].load
	check(
		front_moving < front_static,
		"при разгоне передняя ось должна разгружаться: %.0f против %.0f" % [front_moving, front_static]
	)


func test_accelerates_like_a_loaded_truck() -> void:
	await _spawn()
	await _drive(8.0, 1.0)
	var speed := truck.forward_speed
	check_between(speed, 14.0, 34.0, "скорость через восемь секунд разгона, м/с")
	check_greater(float(truck.drivetrain.gear), 1.0, "к этому моменту автомат должен переключиться")
	check(is_finite(speed), "скорость обязана оставаться числом")


func test_brakes_to_a_stop_within_a_sane_distance() -> void:
	await _spawn()
	await _drive(8.0, 1.0)
	var entry_speed := truck.forward_speed
	var start := truck.global_position
	await _drive(9.0, 0.0, 1.0)
	var distance := start.distance_to(truck.global_position)
	check(absf(truck.forward_speed) < 0.6, "машина должна остановиться: %.2f м/с" % truck.forward_speed)
	# Замедление около 0.5 g на хамаде — примерно вдвое длиннее асфальтового.
	var implied := entry_speed * entry_speed / (2.0 * maxf(distance, 0.1)) / Config.gravity
	check_between(implied, 0.25, 0.85, "среднее замедление в долях g")


func test_soft_sand_costs_you_speed() -> void:
	await _spawn(&"gravel")
	await _drive(8.0, 1.0)
	var on_gravel := truck.forward_speed
	after_each()
	await _spawn(&"sand_soft")
	await _drive(8.0, 1.0)
	var on_sand := truck.forward_speed
	check_greater(
		on_gravel - on_sand, 3.0,
		"по рыхлому песку машина обязана ехать заметно медленнее: %.1f против %.1f" % [on_gravel, on_sand]
	)


func test_deflating_tyres_pays_off_in_the_dunes() -> void:
	await _spawn(&"sand_soft", 2.4)
	await _drive(8.0, 1.0)
	var pumped := truck.forward_speed
	after_each()
	await _spawn(&"sand_soft", 1.0)
	await _drive(8.0, 1.0)
	var deflated := truck.forward_speed
	check_greater(
		deflated, pumped + 1.0,
		"спущенные колёса должны везти лучше накачанных: %.1f против %.1f" % [deflated, pumped]
	)


func test_steering_turns_the_truck_the_right_way() -> void:
	await _spawn()
	await _drive(5.0, 0.6)
	var heading_before := -truck.global_transform.basis.z
	await _drive(3.0, 0.4, 0.0, 1.0)
	var heading_after := -truck.global_transform.basis.z
	var cross := heading_before.cross(heading_after)
	check(cross.y < -0.02, "руль вправо должен поворачивать машину вправо")
	check_greater(
		heading_before.angle_to(heading_after), 0.15, "за три секунды машина должна заметно довернуть"
	)


func test_state_never_goes_to_nan() -> void:
	await _spawn(&"sand_soft")
	await _drive(4.0, 1.0, 0.0, 0.8)
	await _drive(2.0, 0.0, 1.0, -1.0)
	check(truck.global_position.is_finite(), "положение должно оставаться конечным")
	check(truck.linear_velocity.is_finite(), "скорость должна оставаться конечной")
	check(truck.angular_velocity.is_finite(), "угловая скорость должна оставаться конечной")
	for wheel: VehicleWheel in truck.wheels:
		check(is_finite(wheel.angular_velocity), "обороты колеса должны оставаться числом")
		check(is_finite(wheel.load), "нагрузка на колесо должна оставаться числом")
		check(is_finite(wheel.slip_ratio), "проскальзывание должно оставаться числом")
