class_name Drivetrain
extends RefCounted
## Двигатель, сцепление, коробка, раздатка, дифференциалы.
##
## Считает ровно одно: сколько момента приходит на каждое ведущее колесо. Всё
## остальное — обороты, температура, расход — побочные продукты того же
## расчёта, а не отдельная имитация «для приборов».

signal stalled()
signal gear_changed(gear: int)

enum Mode { AUTOMATIC, MANUAL }

const AMBIENT_TEMP := 42.0

var config: VehicleConfig
var mode: Mode = Mode.AUTOMATIC

var running: bool = true
var engine_omega: float = 0.0
## -1 задняя, 0 нейтраль, 1..n передача.
var gear: int = 0
var clutch_engagement: float = 0.0
var low_range: bool = false
var awd: bool = true
var diff_locked: bool = false

## Доля момента на переднюю ось при включённом полном приводе.
var front_bias: float = 0.38

var throttle_effective: float = 0.0
var clutch_torque: float = 0.0
var engine_torque: float = 0.0
var fuel_rate: float = 0.0  ## литров в час
var coolant_temp: float = AMBIENT_TEMP
## Множитель мощности от износа и перегрева, 0..1.
var health: float = 1.0

var _shift_timer: float = 0.0
var _pending_gear: int = 0
var _shift_cooldown: float = 0.0
var _front_wheels: Array[VehicleWheel] = []
var _rear_wheels: Array[VehicleWheel] = []


func setup(vehicle_config: VehicleConfig, wheels: Array[VehicleWheel]) -> void:
	config = vehicle_config
	engine_omega = rpm_to_omega(config.idle_rpm)
	coolant_temp = AMBIENT_TEMP
	_front_wheels.clear()
	_rear_wheels.clear()
	# В Godot вперёд — это -Z, поэтому передняя ось имеет отрицательный Z.
	for wheel: VehicleWheel in wheels:
		if not wheel.spec.driven:
			continue
		if wheel.spec.position.z < 0.0:
			_front_wheels.append(wheel)
		else:
			_rear_wheels.append(wheel)


static func rpm_to_omega(rpm: float) -> float:
	return rpm * TAU / 60.0


static func omega_to_rpm(omega: float) -> float:
	return omega * 60.0 / TAU


func rpm() -> float:
	return omega_to_rpm(engine_omega)


func transfer_ratio() -> float:
	return config.transfer_low if low_range else config.transfer_high


func total_ratio() -> float:
	return config.gear_ratio(gear) * transfer_ratio() * config.final_drive


func is_shifting() -> bool:
	return _shift_timer > 0.0


## Скорость, на которой машина поедет при текущих оборотах и передаче, м/с.
## Нужна автомату и подсказке «переключись».
func speed_at_rpm(target_rpm: float, target_gear: int) -> float:
	var ratio := config.gear_ratio(target_gear) * transfer_ratio() * config.final_drive
	if absf(ratio) < 0.001:
		return 0.0
	var radius := _average_driven_radius()
	return rpm_to_omega(target_rpm) / ratio * radius


func _average_driven_radius() -> float:
	var total := 0.0
	var count := 0
	for wheel: VehicleWheel in _front_wheels + _rear_wheels:
		total += wheel.spec.radius
		count += 1
	return total / maxf(float(count), 1.0)


## Главный шаг. `speed` — продольная скорость кузова, м/с.
func update(dt: float, input: VehicleInput, speed: float) -> void:
	_shift_cooldown = maxf(_shift_cooldown - dt, 0.0)
	_update_shifting(dt, input, speed)

	if not running:
		_update_starter(dt, input)
		_apply_drive_torque(0.0)
		return

	var ratio := total_ratio()
	var shaft_omega := _driven_shaft_omega(ratio)
	_update_clutch(dt, input, ratio, shaft_omega)

	engine_torque = _engine_torque(dt, input)
	clutch_torque = _clutch_torque(shaft_omega)

	engine_omega += (engine_torque - clutch_torque) / maxf(config.engine_inertia, 0.01) * dt
	engine_omega = clampf(engine_omega, 0.0, rpm_to_omega(config.max_rpm * 1.08))

	if clutch_engagement > 0.55 and rpm() < config.idle_rpm * 0.42:
		running = false
		engine_omega = 0.0
		stalled.emit()
		EventBus.engine_stalled.emit()

	var axle_torque := clutch_torque * ratio * config.driveline_efficiency
	_apply_drive_torque(axle_torque)

	_update_thermal(dt, speed)
	_update_fuel(dt)


func _update_starter(dt: float, input: VehicleInput) -> void:
	engine_omega = maxf(engine_omega - 6.0 * dt, 0.0)
	if input.starter and input.ignition:
		running = true
		engine_omega = rpm_to_omega(config.idle_rpm * 0.92)


## Крутящий момент на коленвале с учётом холостого хода, отсечки и здоровья.
func _engine_torque(dt: float, input: VehicleInput) -> float:
	var current_rpm := rpm()
	var demand := clampf(input.throttle, 0.0, 1.0)

	# Регулятор холостого хода. Реальный дизель держит обороты сам, и без этого
	# машина глохнет каждый раз, когда игрок отпускает газ на светофоре.
	if current_rpm < config.idle_rpm + 120.0:
		var deficit := (config.idle_rpm + 120.0 - current_rpm) / 400.0
		demand = maxf(demand, clampf(deficit, 0.0, 0.42))

	throttle_effective = demand

	var torque := config.torque_at(current_rpm) * demand * health
	# Отсечка: момент срезается не обрывом, а за 300 об/мин до предела.
	if current_rpm > config.redline_rpm:
		var over := (current_rpm - config.redline_rpm) / maxf(config.max_rpm - config.redline_rpm, 1.0)
		torque *= clampf(1.0 - over * 1.4, 0.0, 1.0)

	# Насосные потери и трение растут с оборотами — это и есть торможение двигателем.
	var friction := config.engine_friction * (0.5 + current_rpm / maxf(config.max_rpm, 1.0))
	torque -= friction * (1.0 - demand * 0.65)
	# На нулевых оборотах глохнущий двигатель не должен раскручиваться назад.
	if engine_omega < 1.0 and torque < 0.0:
		torque = 0.0
	return torque


func _driven_shaft_omega(ratio: float) -> float:
	if absf(ratio) < 0.001:
		return engine_omega
	var total := 0.0
	var count := 0
	for wheel: VehicleWheel in _active_driven_wheels():
		total += wheel.angular_velocity
		count += 1
	if count == 0:
		return engine_omega
	return total / float(count) * ratio


func _active_driven_wheels() -> Array[VehicleWheel]:
	if awd:
		return _front_wheels + _rear_wheels
	return _rear_wheels if not _rear_wheels.is_empty() else _front_wheels


func _update_clutch(dt: float, input: VehicleInput, ratio: float, shaft_omega: float) -> void:
	var target := 0.0
	if is_shifting() or absf(ratio) < 0.001:
		target = 0.0
	elif mode == Mode.MANUAL:
		target = clampf(input.clutch, 0.0, 1.0)
	else:
		# Автомат отпускает сцепление тем сильнее, чем выше обороты над холостыми
		# и чем быстрее уже крутятся колёса. Отдельная защита: на низких оборотах
		# под нагрузкой сцепление проскальзывает вместо того, чтобы заглушить мотор.
		var over_idle := (rpm() - config.idle_rpm * 1.04) / maxf(config.idle_rpm * 0.7, 1.0)
		var by_rpm := clampf(over_idle, 0.0, 1.0)
		var by_speed := clampf(absf(shaft_omega) / maxf(rpm_to_omega(config.idle_rpm), 1.0), 0.0, 1.0)
		target = maxf(by_rpm, by_speed)
		if rpm() < config.idle_rpm * 0.85:
			target = 0.0
	var rate := 9.0 if target > clutch_engagement else 14.0
	clutch_engagement = move_toward(clutch_engagement, target, rate * dt)


func _clutch_torque(shaft_omega: float) -> float:
	if clutch_engagement <= 0.001 or absf(total_ratio()) < 0.001:
		return 0.0
	var slip := engine_omega - shaft_omega
	var stiffness := config.clutch_capacity / 12.0
	var capacity := config.clutch_capacity * clutch_engagement
	return clampf(slip * stiffness, -capacity, capacity) * clutch_engagement


## Раскидывает момент по осям и колёсам с учётом дифференциалов.
func _apply_drive_torque(axle_torque: float) -> void:
	for wheel: VehicleWheel in _front_wheels + _rear_wheels:
		wheel.drive_torque = 0.0
	if _front_wheels.is_empty() and _rear_wheels.is_empty():
		return

	var front_share := 0.0
	var rear_share := 0.0
	if awd and not _front_wheels.is_empty() and not _rear_wheels.is_empty():
		front_share = front_bias
		rear_share = 1.0 - front_bias
		# Межосевой дифференциал: при блокировке момент перетекает к отстающей оси.
		var front_omega := _axle_omega(_front_wheels)
		var rear_omega := _axle_omega(_rear_wheels)
		var lock := config.diff_lock_locked if diff_locked else config.diff_lock_open
		var transfer := clampf(lock * (rear_omega - front_omega) * 60.0, -900.0, 900.0)
		_distribute_axle(_front_wheels, axle_torque * front_share + transfer)
		_distribute_axle(_rear_wheels, axle_torque * rear_share - transfer)
		return

	if not _rear_wheels.is_empty():
		rear_share = 1.0
		_distribute_axle(_rear_wheels, axle_torque * rear_share)
	elif not _front_wheels.is_empty():
		front_share = 1.0
		_distribute_axle(_front_wheels, axle_torque * front_share)


func _axle_omega(wheels: Array[VehicleWheel]) -> float:
	if wheels.is_empty():
		return 0.0
	var total := 0.0
	for wheel: VehicleWheel in wheels:
		total += wheel.angular_velocity
	return total / float(wheels.size())


## Свободный дифференциал делит момент поровну; блокировка добавляет вязкую
## связь, которая тянет буксующее колесо назад, а стоящее — вперёд.
func _distribute_axle(wheels: Array[VehicleWheel], torque: float) -> void:
	if wheels.is_empty():
		return
	var base := torque / float(wheels.size())
	if wheels.size() != 2:
		for wheel: VehicleWheel in wheels:
			wheel.drive_torque = base
		return
	var lock := config.diff_lock_locked if diff_locked else config.diff_lock_open
	var difference := wheels[0].angular_velocity - wheels[1].angular_velocity
	var coupling := clampf(lock * difference * 80.0, -1200.0, 1200.0)
	wheels[0].drive_torque = base - coupling
	wheels[1].drive_torque = base + coupling


# --- Переключения ----------------------------------------------------------

func _update_shifting(dt: float, input: VehicleInput, speed: float) -> void:
	if _shift_timer > 0.0:
		_shift_timer -= dt
		if _shift_timer <= 0.0:
			_set_gear(_pending_gear)
		return

	if input.shift_up:
		_request_manual(1, speed)
	elif input.shift_down:
		_request_manual(-1, speed)
	elif mode == Mode.AUTOMATIC:
		_update_automatic(input, speed)


func _request_manual(direction: int, speed: float) -> void:
	var target := gear + direction
	# Через нейтраль в заднюю пускаем только на почти остановленной машине.
	if target < 0 and absf(speed) > 1.5:
		target = 0
	target = clampi(target, -1, config.top_gear())
	if target != gear:
		_begin_shift(target)


func _update_automatic(input: VehicleInput, speed: float) -> void:
	if _shift_cooldown > 0.0:
		return
	if gear <= 0:
		# Трогаемся с места: вперёд по газу, назад — по тормозу на стоящей машине.
		if input.throttle > 0.05 and speed > -0.5:
			_begin_shift(1)
		elif input.brake > 0.35 and speed < 0.4 and gear == 0:
			_begin_shift(-1)
		return

	var current_rpm := rpm()
	var up_rpm := config.redline_rpm * 0.88
	var down_rpm := config.idle_rpm * 1.75

	if gear < config.top_gear() and current_rpm > up_rpm and input.brake < 0.1:
		_begin_shift(gear + 1)
		return
	if gear > 1 and current_rpm < down_rpm:
		_begin_shift(gear - 1)
		return
	# Кикдаун: полный газ на низких оборотах — вниз, даже если обороты в норме.
	if gear > 1 and input.throttle > 0.9 and current_rpm < config.redline_rpm * 0.55:
		_begin_shift(gear - 1)
		return
	if gear == 1 and absf(speed) < 0.3 and input.throttle < 0.05:
		_begin_shift(0)


func _begin_shift(target: int) -> void:
	if target == gear:
		return
	_pending_gear = clampi(target, -1, config.top_gear())
	_shift_timer = config.shift_time
	_shift_cooldown = config.shift_time + 0.45


func _set_gear(value: int) -> void:
	if gear == value:
		return
	gear = value
	gear_changed.emit(gear)
	EventBus.gear_changed.emit(gear)


func force_gear(value: int) -> void:
	_shift_timer = 0.0
	_set_gear(clampi(value, -1, config.top_gear()))


# --- Тепло и расход --------------------------------------------------------

func _update_thermal(dt: float, speed: float) -> void:
	var power_kw := maxf(engine_torque, 0.0) * engine_omega / 1000.0
	# В тепло уходит примерно столько же, сколько на вал: КПД дизеля около 40%.
	var heat := power_kw * 1.35
	var airflow := 0.30 + 0.70 * clampf(absf(speed) / 22.0, 0.0, 1.0)
	var cooling := (
		config.cooling_capacity
		* airflow
		* clampf((coolant_temp - AMBIENT_TEMP) / 55.0, 0.0, 1.6)
	)
	coolant_temp += (heat - cooling) / maxf(config.thermal_mass, 1.0) * dt
	coolant_temp = clampf(coolant_temp, AMBIENT_TEMP, 135.0)
	# Перегрев душит мотор — это и есть наказание за ползание по дюнам на второй.
	if coolant_temp > 104.0:
		health = minf(health, clampf(1.0 - (coolant_temp - 104.0) / 40.0, 0.35, 1.0))


func _update_fuel(dt: float) -> void:
	var power_kw := maxf(engine_torque, 0.0) * engine_omega / 1000.0
	var kg_per_hour := config.bsfc * power_kw / 1000.0
	# Даже на холостых мотор ест — иначе ночёвка с работающим двигателем бесплатна.
	kg_per_hour += 0.55 * clampf(rpm() / config.idle_rpm, 0.0, 2.0)
	fuel_rate = kg_per_hour / maxf(config.fuel_density, 0.1)


## Сколько литров сожжено за шаг.
func fuel_used(dt: float) -> float:
	return fuel_rate * dt / 3600.0
