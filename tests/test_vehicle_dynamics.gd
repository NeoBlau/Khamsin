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


func test_launches_like_a_truck_with_two_hundred_horsepower() -> void:
	# Разгон — самая заметная характеристика машины и самая лёгкая для того,
	# чтобы незаметно её испортить: слишком усердная противобуксовочная режет
	# газ на старте, и шеститонник разгоняется как гружёная телега.
	await _spawn(&"asphalt")
	truck.input.throttle = 1.0
	var elapsed := 0.0
	var to_thirty := -1.0
	var to_fifty := -1.0
	while elapsed < 20.0:
		await simulate(1.0 / 120.0)
		elapsed += 1.0 / 120.0
		if to_thirty < 0.0 and truck.forward_speed >= 30.0 / 3.6:
			to_thirty = elapsed
		if to_fifty < 0.0 and truck.forward_speed >= 50.0 / 3.6:
			to_fifty = elapsed
			break
	truck.input.throttle = 0.0
	check_greater(to_thirty, 0.0, "до тридцати километров в час машина обязана разогнаться")
	check_between(to_thirty, 1.5, 6.0, "секунд до 30 км/ч на твёрдом покрытии")
	check_greater(to_fifty, 0.0, "и до пятидесяти тоже")
	check_between(to_fifty, 3.0, 12.0, "секунд до 50 км/ч")


func test_traction_control_does_not_strangle_the_launch() -> void:
	await _spawn(&"gravel")
	Settings.assist_traction = true
	await _drive(6.0, 1.0)
	var assisted := truck.forward_speed
	after_each()

	await _spawn(&"gravel")
	Settings.assist_traction = false
	await _drive(6.0, 1.0)
	var raw := truck.forward_speed
	Settings.assist_traction = true
	check_greater(
		assisted, raw * 0.75,
		"с помощником машина не должна ехать сильно хуже: %.1f против %.1f" % [assisted, raw]
	)


func test_a_wrecked_suspension_still_carries_the_truck() -> void:
	# Изношенная подвеска должна возить плохо, а не переставать существовать.
	# При нулевой эффективности машина садится на раму, колёса повисают в
	# воздухе и крутятся вхолостую — из такого состояния игрок не выберется
	# ничем, и это худший вид поломки, какой может быть в игре про дорогу.
	await _spawn()
	var healthy := truck.global_position.y
	truck.suspension_health = 0.0
	await simulate(3.0)
	var wrecked := truck.global_position.y

	check(wrecked < healthy, "убитая подвеска должна просаживать машину")
	check_greater(
		wrecked, healthy - 0.32, "но не настолько, чтобы рама легла на землю"
	)
	var grounded := 0
	var load := 0.0
	for wheel: VehicleWheel in truck.wheels:
		if wheel.grounded:
			grounded += 1
		load += wheel.load
	check_equal(grounded, 4, "колёса должны остаться на земле")
	check_greater(load, truck.mass * Config.gravity * 0.5, "и продолжать нести вес")

	await _drive(6.0, 1.0)
	check_greater(truck.forward_speed, 2.0, "и машина должна ехать, пусть и хуже")


func test_landings_do_not_destroy_the_suspension_in_one_go() -> void:
	await _spawn()
	truck.global_position += Vector3.UP * 3.5
	await simulate(3.0)
	check_greater(
		truck.suspension_health, 0.8,
		"падение с трёх метров не должно съедать пятую часть ресурса подвески"
	)


func test_reaches_a_plausible_top_speed() -> void:
	# Потолок скорости определяется тягой против сопротивления. Любая лишняя
	# сила — например, демпфирование скорости, включённое в движке по
	# умолчанию, — срезает его вдвое, и найти это по коду почти невозможно:
	# тяга на месте, явное сопротивление на месте, а разгона нет.
	await _spawn(&"asphalt")
	await _drive(50.0, 1.0)
	var top := truck.forward_speed * 3.6
	check_between(top, 95.0, 190.0, "максимальная скорость на асфальте, км/ч")
	check_greater(float(truck.drivetrain.gear), 3.0, "на максималке должна стоять высокая передача")


func test_coasting_slows_down_at_a_believable_rate() -> void:
	# Обратная проверка к предыдущей: без газа машина обязана замедляться, но
	# от воздуха и качения, а не от невидимого тормоза. Замедление накатом у
	# гружёного грузовика на семидесяти — порядка 0.05 g.
	await _spawn(&"asphalt")
	await _drive(30.0, 1.0)
	var entry := truck.forward_speed
	check_greater(entry, 15.0, "для наката нужна скорость")
	var start := truck.global_position
	await _drive(6.0, 0.0)
	var lost := entry - truck.forward_speed
	var deceleration := lost / 6.0 / Config.gravity
	check_between(deceleration, 0.01, 0.10, "замедление накатом в долях g")
	check_greater(start.distance_to(truck.global_position), 80.0, "и за шесть секунд надо проехать накатом")
