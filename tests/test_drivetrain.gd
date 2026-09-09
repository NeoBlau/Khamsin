extends TestCase
## Трансмиссия без сцены: кривая момента, передачи, сцепление, расход, нагрев.

var config: VehicleConfig
var wheels: Array[VehicleWheel] = []
var drivetrain: Drivetrain
var input: VehicleInput


func before_each() -> void:
	Catalog.ensure_loaded()
	config = Catalog.vehicle(&"tabuk_6t")
	wheels = []
	for spec: VehicleConfig.WheelSpec in config.wheels:
		var wheel := VehicleWheel.new()
		wheel.setup(spec, config)
		wheels.append(wheel)
	drivetrain = Drivetrain.new()
	drivetrain.setup(config, wheels)
	input = VehicleInput.new()


func test_config_loaded() -> void:
	check(config != null, "конфигурация «Табук» должна грузиться")
	check_equal(config.wheels.size(), 4, "у машины четыре колеса")
	check_equal(config.top_gear(), 6, "шесть передач вперёд")


func test_torque_curve_interpolates_and_clamps() -> void:
	check_near(config.torque_at(1600.0), 700.0, 0.1, "точка кривой должна возвращаться как есть")
	check_near(config.torque_at(1400.0), 660.0, 0.1, "между точками — линейная интерполяция")
	check_near(config.torque_at(100.0), 300.0, 0.1, "ниже кривой держим первое значение")
	check_near(config.torque_at(9000.0), 330.0, 0.1, "выше кривой держим последнее")


func test_peak_power_is_plausible_for_a_truck() -> void:
	var peak := config.peak_power()
	check_between(peak.x, 120.0, 200.0, "максимальная мощность, кВт")
	check_between(peak.y, 1800.0, 3000.0, "обороты максимальной мощности")
	check_between(config.peak_torque(), 500.0, 900.0, "максимальный момент, Н·м")


func test_gear_ratios_are_descending() -> void:
	for gear: int in range(1, config.top_gear()):
		check(
			config.gear_ratio(gear) > config.gear_ratio(gear + 1),
			"передача %d должна быть длиннее предыдущей" % (gear + 1)
		)
	check(config.gear_ratio(-1) < 0.0, "задняя передача должна вращать в обратную сторону")
	check_near(config.gear_ratio(0), 0.0, 1e-6, "на нейтрали связи с колёсами нет")


func test_low_range_multiplies_torque() -> void:
	drivetrain.force_gear(1)
	var high := absf(drivetrain.total_ratio())
	drivetrain.low_range = true
	var low := absf(drivetrain.total_ratio())
	check_near(low / high, config.transfer_low, 0.001, "пониженная должна давать заявленный множитель")


func test_idle_governor_holds_engine_running() -> void:
	drivetrain.force_gear(0)
	for _i: int in 600:
		drivetrain.update(1.0 / 120.0, input, 0.0)
	check(drivetrain.running, "без газа на нейтрали двигатель глохнуть не должен")
	check_between(drivetrain.rpm(), config.idle_rpm * 0.85, config.idle_rpm * 1.45, "холостые обороты")


func test_throttle_revs_engine_in_neutral() -> void:
	# Автомат из нейтрали сам уходит на первую, поэтому проверяем на ручной.
	drivetrain.mode = Drivetrain.Mode.MANUAL
	drivetrain.force_gear(0)
	input.throttle = 1.0
	for _i: int in 240:
		drivetrain.update(1.0 / 120.0, input, 0.0)
	check_greater(drivetrain.rpm(), config.redline_rpm * 0.9, "на нейтрали газ должен раскрутить мотор")
	check(
		drivetrain.rpm() < config.max_rpm,
		"отсечка не должна пускать выше максимума: %.0f" % drivetrain.rpm()
	)


func test_automatic_upshifts_as_wheels_spin_up() -> void:
	input.throttle = 1.0
	var speed := 0.0
	for i: int in 1800:
		# Подменяем машину: колёса раскручиваются равномерно, как при разгоне.
		speed = float(i) / 1800.0 * 28.0
		for wheel: VehicleWheel in wheels:
			wheel.angular_velocity = speed / wheel.spec.radius
		drivetrain.update(1.0 / 120.0, input, speed)
	check_greater(float(drivetrain.gear), 2.0, "к 100 км/ч автомат должен уйти выше второй")
	check(drivetrain.gear <= config.top_gear(), "выше последней передачи уходить некуда")


func test_clutch_transmits_torque_only_when_engaged() -> void:
	drivetrain.force_gear(1)
	input.throttle = 1.0
	for _i: int in 120:
		drivetrain.update(1.0 / 120.0, input, 0.0)
	var driven := 0.0
	for wheel: VehicleWheel in wheels:
		driven += absf(wheel.drive_torque)
	check_greater(driven, 100.0, "на первой передаче с газом момент должен дойти до колёс")
	check_between(drivetrain.clutch_engagement, 0.0, 1.0, "схваченность сцепления в допустимых границах")


func test_open_differential_sends_torque_to_the_spinning_wheel() -> void:
	drivetrain.force_gear(1)
	drivetrain.awd = false
	input.throttle = 1.0
	for _i: int in 60:
		drivetrain.update(1.0 / 120.0, input, 0.0)
	# Правое заднее буксует, левое стоит.
	wheels[2].angular_velocity = 0.0
	wheels[3].angular_velocity = 40.0
	drivetrain.update(1.0 / 120.0, input, 0.0)
	var open_gap := wheels[2].drive_torque - wheels[3].drive_torque
	drivetrain.diff_locked = true
	drivetrain.update(1.0 / 120.0, input, 0.0)
	var locked_gap := wheels[2].drive_torque - wheels[3].drive_torque
	check_greater(
		locked_gap, open_gap,
		"блокировка должна перекидывать момент на стоящее колесо сильнее свободного дифференциала"
	)
	check_greater(locked_gap, 0.0, "стоящее колесо должно получать больше буксующего")


func test_fuel_burn_matches_declared_consumption() -> void:
	drivetrain.mode = Drivetrain.Mode.MANUAL
	drivetrain.force_gear(3)
	input.throttle = 1.0
	# Колёса держим на оборотах, которые на третьей дают около 2000 об/мин —
	# рабочая точка, а не отсечка, иначе момент срезан и расхода нет.
	for _i: int in 240:
		for wheel: VehicleWheel in wheels:
			wheel.angular_velocity = 22.0
		drivetrain.update(1.0 / 120.0, input, 11.0)
	check_between(drivetrain.rpm(), 1500.0, 2600.0, "рабочая точка по оборотам")
	# Гружёный дизель на полном газу — примерно 30-70 литров в час.
	check_between(drivetrain.fuel_rate, 20.0, 80.0, "расход под нагрузкой, литров в час")
	var used := drivetrain.fuel_used(3600.0)
	check_near(used, drivetrain.fuel_rate, 0.001, "литры за час должны совпасть с часовым расходом")


func test_engine_heats_up_under_load_and_derates() -> void:
	drivetrain.force_gear(1)
	input.throttle = 1.0
	var start := drivetrain.coolant_temp
	for _i: int in 12000:
		for wheel: VehicleWheel in wheels:
			wheel.angular_velocity = 6.0
		drivetrain.update(1.0 / 120.0, input, 3.0)
	check_greater(drivetrain.coolant_temp, start + 20.0, "ползание на первой должно греть мотор")
	check(drivetrain.coolant_temp <= 135.0, "температура не должна уходить за физический предел")


func test_engine_stalls_when_load_kills_revs() -> void:
	drivetrain.force_gear(1)
	drivetrain.mode = Drivetrain.Mode.MANUAL
	input.clutch = 1.0
	input.throttle = 0.0
	# Колёса стоят намертво — двигатель на схваченном сцеплении обязан заглохнуть.
	for _i: int in 600:
		for wheel: VehicleWheel in wheels:
			wheel.angular_velocity = 0.0
		drivetrain.update(1.0 / 120.0, input, 0.0)
		if not drivetrain.running:
			break
	check(not drivetrain.running, "на схваченном сцеплении при стоящих колёсах мотор должен заглохнуть")
	input.starter = true
	input.ignition = true
	drivetrain.update(1.0 / 120.0, input, 0.0)
	check(drivetrain.running, "стартер должен заводить обратно")


func test_automatic_does_not_climb_gears_on_spinning_wheels() -> void:
	# Классическая ловушка автомата во внедорожной игре: колёса буксуют в песке,
	# обороты высокие, машина стоит — и коробка уходит на высшую передачу, где
	# момента нет и выехать уже невозможно.
	input.throttle = 1.0
	for _i: int in 1200:
		for wheel: VehicleWheel in wheels:
			wheel.angular_velocity = 90.0
		drivetrain.update(1.0 / 120.0, input, 0.6)
	check(
		drivetrain.gear <= 2,
		"при стоящей машине автомат не должен уходить выше второй, получили %d" % drivetrain.gear
	)


func test_automatic_downshifts_when_speed_drops() -> void:
	input.throttle = 1.0
	var speed := 26.0
	for i: int in 1800:
		speed = 26.0 if i < 900 else 3.0
		for wheel: VehicleWheel in wheels:
			wheel.angular_velocity = speed / wheel.spec.radius
		drivetrain.update(1.0 / 120.0, input, speed)
		if i == 899:
			check_greater(float(drivetrain.gear), 2.0, "на скорости должна стоять высокая передача")
	check(drivetrain.gear <= 2, "после падения скорости автомат обязан уйти вниз")
