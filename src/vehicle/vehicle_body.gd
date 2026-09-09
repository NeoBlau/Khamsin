class_name VehicleBody
extends RigidBody3D
## Машина целиком: кузов, подвеска, шины, трансмиссия, повреждения.
##
## Порядок шага важен и специально жёсткий:
##   1. опрос подвески — где земля, какое сжатие;
##   2. стабилизаторы — они меняют нагрузку на колёсах до расчёта шин;
##   3. подшаги: шины считают силы и крутят колёса;
##   4. трансмиссия раздаёт момент по колёсам на следующий шаг;
##   5. одна суммарная сила и один суммарный момент уходят в кузов.
##
## Силы прикладываются через `apply_central_force` и `apply_torque` вручную, а
## не через `apply_force(force, position)`: так не приходится гадать, от какой
## точки движок считает плечо, и модель ведёт себя одинаково на Jolt и на
## встроенной физике.

signal telemetry_updated()

const SUBSTEPS := 4
const STUCK_SPEED := 0.6
const STUCK_TIME := 3.0

@export var config_id: StringName = &"tabuk_6t"
@export var player_controlled: bool = true
## Маска слоёв, по которым щупает подвеска. Совпадает со слоем ландшафта.
@export_flags_3d_physics var ground_mask: int = 1

var config: VehicleConfig
var wheels: Array[VehicleWheel] = []
var drivetrain: Drivetrain
var input: VehicleInput = VehicleInput.new()
## Команда после помощников. В неё пишут АБС и противобуксовочная, а `input`
## остаётся тем, что просил водитель.
var command: VehicleInput = VehicleInput.new()

## Заполняется миром: по мировой точке возвращает покрытие под колесом.
var surface_provider: Callable = Callable()
## Скорость воздуха в мировых координатах, м/с. Ставит погода.
var wind_velocity: Vector3 = Vector3.ZERO

var fuel: float = 0.0
var odometer: float = 0.0
var engine_health: float = 1.0
var body_health: float = 1.0
var suspension_health: float = 1.0
var cargo_mass: float = 0.0

var speed: float = 0.0
var forward_speed: float = 0.0
var lateral_speed: float = 0.0
var is_stuck: bool = false
var rolled_over: bool = false

var _steer_input: float = 0.0
var _steer_angle: float = 0.0
var _abs_scale: PackedFloat32Array = PackedFloat32Array()
var _traction_cut: float = 1.0
var _stuck_timer: float = 0.0
var _rollover_timer: float = 0.0
var _previous_velocity: Vector3 = Vector3.ZERO
var _shock_filtered: float = 0.0
var _wheel_visuals: Array[Node3D] = []
var _distance_since_sync: float = 0.0


func _ready() -> void:
	Catalog.ensure_loaded()
	var base := Catalog.vehicle(config_id)
	# Купленное оборудование меняет характеристики. Правится копия: конфигурация
	# из справочника общая, и менять её значило бы менять все машины сразу.
	config = Upgrades.configure(base) if player_controlled and base != null else base
	if config == null:
		push_error("VehicleBody: нет конфигурации '%s'" % config_id)
		set_physics_process(false)
		return
	_build_from_config()
	if player_controlled:
		_restore_from_state()


func _build_from_config() -> void:
	mass = config.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = config.center_of_mass
	if config.inertia.length_squared() > 0.0:
		inertia = config.inertia
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	# Трение и упругость кузова: он не должен ни прилипать к скале, ни скакать.
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.35
	physics_material_override.bounce = 0.05

	wheels.clear()
	_abs_scale.resize(config.wheels.size())
	for i: int in config.wheels.size():
		var wheel := VehicleWheel.new()
		wheel.setup(config.wheels[i], config)
		wheels.append(wheel)
		_abs_scale[i] = 1.0

	_build_collision()

	drivetrain = Drivetrain.new()
	drivetrain.setup(config, wheels)
	drivetrain.mode = (
		Drivetrain.Mode.MANUAL
		if Settings.transmission == Settings.Transmission.MANUAL
		else Drivetrain.Mode.AUTOMATIC
	)
	fuel = config.fuel_capacity
	refresh_cargo_mass()


## Коллизия кузова — две коробки: кабина и грузовая часть. Одной мало: у
## одной коробки на всю длину нижняя грань задевает гребни там, где машина в
## жизни проходит, и наоборот.
func _build_collision() -> void:
	for child: Node in get_children():
		if child is CollisionShape3D:
			child.queue_free()
	var size := config.body_size
	var cab := CollisionShape3D.new()
	cab.name = "CollisionCab"
	var cab_shape := BoxShape3D.new()
	cab_shape.size = Vector3(size.x, size.y, size.z * 0.42)
	cab.shape = cab_shape
	cab.position = config.body_offset + Vector3(0.0, 0.0, -size.z * 0.29)
	add_child(cab)

	var bed := CollisionShape3D.new()
	bed.name = "CollisionBed"
	var bed_shape := BoxShape3D.new()
	bed_shape.size = Vector3(size.x, size.y * 0.62, size.z * 0.58)
	bed.shape = bed_shape
	bed.position = config.body_offset + Vector3(0.0, -size.y * 0.19, size.z * 0.21)
	add_child(bed)


func attach_visuals(chassis: Node3D, wheel_nodes: Array[Node3D]) -> void:
	_wheel_visuals = wheel_nodes
	if chassis != null and chassis.get_parent() == null:
		add_child(chassis)


## Подтягивает состояние машины из сейва.
func _restore_from_state() -> void:
	var state: Dictionary = GameState.vehicle
	fuel = clampf(float(state.get("fuel", config.fuel_capacity)), 0.0, config.fuel_capacity)
	odometer = float(state.get("odometer", 0.0))
	engine_health = float(state.get("engine_health", 1.0))
	body_health = float(state.get("body_health", 1.0))
	suspension_health = float(state.get("suspension_health", 1.0))
	drivetrain.coolant_temp = float(state.get("coolant_temp", Drivetrain.AMBIENT_TEMP))
	var pressures: Array = state.get("tire_pressures", [])
	var wear: Array = state.get("tire_wear", [])
	for i: int in wheels.size():
		if i < pressures.size():
			wheels[i].set_pressure(float(pressures[i]))
		if i < wear.size():
			wheels[i].wear = clampf(float(wear[i]), 0.0, 1.0)
	refresh_cargo_mass()


## Пишет состояние обратно в сейв. Зовётся при остановке в посёлке и на автосейве.
func sync_to_state() -> void:
	if not player_controlled:
		return
	var pressures: Array = []
	var wear: Array = []
	for wheel: VehicleWheel in wheels:
		pressures.append(wheel.pressure)
		wear.append(wheel.wear)
	GameState.vehicle["fuel"] = fuel
	GameState.vehicle["odometer"] = odometer
	GameState.vehicle["engine_health"] = engine_health
	GameState.vehicle["body_health"] = body_health
	GameState.vehicle["suspension_health"] = suspension_health
	GameState.vehicle["coolant_temp"] = drivetrain.coolant_temp
	GameState.vehicle["tire_pressures"] = pressures
	GameState.vehicle["tire_wear"] = wear


func refresh_cargo_mass() -> void:
	cargo_mass = GameState.carried_mass() if player_controlled else 0.0
	mass = config.mass + cargo_mass + fuel * config.fuel_density


# --- Шаг физики ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if config == null:
		return
	if player_controlled:
		_read_player_input(delta)
	input.copy_to(command)

	var xform := global_transform
	var velocity := linear_velocity
	forward_speed = velocity.dot(-xform.basis.z)
	lateral_speed = velocity.dot(xform.basis.x)
	speed = velocity.length()

	_update_steering(delta)
	_probe_wheels(xform, delta)
	_apply_antiroll()

	# Помощники правят команду до того, как её увидит трансмиссия, иначе срез
	# газа противобуксовочной опаздывает на кадр и машина клюёт.
	_apply_brakes(delta)
	drivetrain.health = engine_health * _fuel_starvation()
	drivetrain.update(delta, command, forward_speed)

	var accumulated := _simulate_tires(xform, delta)
	_apply_accumulated(accumulated, xform)
	_apply_aero(xform)

	_consume_fuel(delta)
	_update_diagnostics(delta, velocity)
	_update_visuals(delta)
	input.clear_edges()


func _read_player_input(delta: float) -> void:
	if SceneRouter.is_overlay_open():
		input.throttle = 0.0
		input.brake = 0.0
		input.steer = move_toward(input.steer, 0.0, delta * 4.0)
		return
	input.throttle = Input.get_action_strength(&"throttle")
	input.brake = Input.get_action_strength(&"brake")
	input.handbrake = Input.get_action_strength(&"handbrake")
	input.clutch = 1.0 - Input.get_action_strength(&"clutch")
	_steer_input = Input.get_action_strength(&"steer_right") - Input.get_action_strength(&"steer_left")
	input.steer = _steer_input
	if Input.is_action_just_pressed(&"shift_up"):
		input.shift_up = true
	if Input.is_action_just_pressed(&"shift_down"):
		input.shift_down = true
	if Input.is_action_just_pressed(&"toggle_4wd"):
		drivetrain.awd = not drivetrain.awd
		EventBus.notify("Полный привод: %s" % ("включён" if drivetrain.awd else "выключен"))
	if Input.is_action_just_pressed(&"toggle_diff_lock"):
		drivetrain.diff_locked = not drivetrain.diff_locked
		EventBus.notify("Блокировки: %s" % ("замкнуты" if drivetrain.diff_locked else "разомкнуты"))
	if Input.is_action_just_pressed(&"toggle_low_range"):
		if absf(forward_speed) < 2.0:
			drivetrain.low_range = not drivetrain.low_range
			EventBus.notify("Раздатка: %s" % ("пониженная" if drivetrain.low_range else "прямая"))
		else:
			EventBus.notify("Раздатку включают на месте", &"warning")
	if Input.is_action_just_pressed(&"pressure_up"):
		adjust_pressure(0.2)
	if Input.is_action_just_pressed(&"pressure_down"):
		adjust_pressure(-0.2)
	if Input.is_action_just_pressed(&"recover"):
		request_recovery()
	if not drivetrain.running and input.throttle > 0.1:
		input.starter = true


## Руль поворачивается не мгновенно и на скорости ходит меньше — иначе на
## сотне лёгкое касание клавиши укладывает шеститонник на бок.
func _update_steering(delta: float) -> void:
	var speed_factor := 1.0 / (1.0 + config.steer_speed_falloff * absf(forward_speed) / 30.0)
	var target := clampf(input.steer, -1.0, 1.0) * Settings.steer_sensitivity
	var rate := 3.4 if absf(target) > absf(_steer_angle) else Settings.steer_return_rate * 2.0
	_steer_angle = move_toward(_steer_angle, clampf(target, -1.0, 1.0), rate * delta)
	var max_angle := config.steer_angle_max * speed_factor
	_assign_ackermann(_steer_angle * max_angle)


## Схема Аккермана: внутреннее колесо в повороте стоит круче внешнего, иначе
## передняя ось на малом радиусе скребёт боком.
func _assign_ackermann(angle: float) -> void:
	var steered: Array[VehicleWheel] = []
	for wheel: VehicleWheel in wheels:
		if wheel.spec.steered:
			steered.append(wheel)
	if steered.is_empty():
		return
	if absf(angle) < 0.0005 or steered.size() != 2:
		for wheel: VehicleWheel in steered:
			wheel.steer_angle = angle
		return

	var wheelbase := _wheelbase()
	var track := absf(steered[0].spec.position.x - steered[1].spec.position.x)
	var radius := wheelbase / maxf(absf(tan(angle)), 0.0001)
	var inner := atan(wheelbase / maxf(radius - track * 0.5, 0.4))
	var outer := atan(wheelbase / (radius + track * 0.5))
	var sign_of := signf(angle)
	for wheel: VehicleWheel in steered:
		var is_inner := signf(wheel.spec.position.x) == sign_of
		wheel.steer_angle = sign_of * (inner if is_inner else outer)


func _wheelbase() -> float:
	var front := 0.0
	var rear := 0.0
	for wheel: VehicleWheel in wheels:
		front = minf(front, wheel.spec.position.z)
		rear = maxf(rear, wheel.spec.position.z)
	return maxf(rear - front, 1.0)


func _probe_wheels(xform: Transform3D, delta: float) -> void:
	var space := get_world_3d().direct_space_state
	for wheel: VehicleWheel in wheels:
		wheel.probe(space, xform, get_rid(), ground_mask, delta)
		wheel.antiroll_force = 0.0
		if wheel.grounded:
			wheel.surface = _surface_at(wheel.contact_point)


func _surface_at(point: Vector3) -> Surface:
	if surface_provider.is_valid():
		var result: Variant = surface_provider.call(point)
		if result is Surface:
			return result
	return Surface.default_surface()


## Стабилизаторы связывают колёса одной оси: чем сильнее крен, тем больше они
## перекидывают нагрузку на разгруженную сторону.
func _apply_antiroll() -> void:
	var axles := _axle_pairs()
	for pair: Array in axles:
		var left: VehicleWheel = pair[0]
		var right: VehicleWheel = pair[1]
		var stiffness: float = pair[2]
		if stiffness <= 0.0:
			continue
		var difference := left.compression - right.compression
		var force := difference * stiffness * suspension_health
		left.antiroll_force = -force
		right.antiroll_force = force


func _axle_pairs() -> Array[Array]:
	var groups: Dictionary[int, Array] = {}
	for wheel: VehicleWheel in wheels:
		var key := roundi(wheel.spec.position.z * 10.0)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(wheel)
	var out: Array[Array] = []
	var keys: Array = groups.keys()
	keys.sort()
	for i: int in keys.size():
		var group: Array = groups[keys[i]]
		if group.size() != 2:
			continue
		var stiffness := config.antiroll_front if i == 0 else config.antiroll_rear
		var left: VehicleWheel = group[0]
		var right: VehicleWheel = group[1]
		if left.spec.position.x > right.spec.position.x:
			var swap := left
			left = right
			right = swap
		out.append([left, right, stiffness])
	return out


func _apply_brakes(delta: float) -> void:
	var demand := clampf(command.brake, 0.0, 1.0)
	var handbrake := clampf(command.handbrake, 0.0, 1.0)
	for i: int in wheels.size():
		var wheel := wheels[i]
		var torque := config.brake_torque * demand * wheel.spec.brake_bias * 2.0
		if wheel.spec.handbrake:
			torque = maxf(torque, config.handbrake_torque * handbrake)
		# ABS отпускает конкретное колесо, а не тормоз целиком.
		if Settings.assist_abs and demand > 0.05 and wheel.grounded:
			var locking := wheel.slip_ratio < -0.22 and absf(wheel.contact_speed_long) > 2.0
			var target := 0.35 if locking else 1.0
			_abs_scale[i] = move_toward(_abs_scale[i], target, delta * 12.0)
		else:
			_abs_scale[i] = 1.0
		wheel.brake_torque = maxf(torque * _abs_scale[i], 0.0)

	# Противобуксовочная режет газ целиком: раздельный привод по колёсам на
	# такой машине не стоит, а имитировать его было бы враньём.
	if Settings.assist_traction:
		var worst := 0.0
		for wheel: VehicleWheel in wheels:
			if wheel.spec.driven and wheel.grounded:
				worst = maxf(worst, wheel.slip_ratio)
		var target := 1.0 if worst < 0.45 else clampf(1.0 - (worst - 0.45) * 0.8, 0.25, 1.0)
		_traction_cut = move_toward(_traction_cut, target, delta * 6.0)
		command.throttle = input.throttle * _traction_cut
	else:
		_traction_cut = 1.0


## Считает шины подшагами и возвращает [сумма сил, сумма моментов] в мировых
## координатах.
func _simulate_tires(xform: Transform3D, delta: float) -> Array:
	var com := xform * center_of_mass
	var total_force := Vector3.ZERO
	var total_torque := Vector3.ZERO
	var body_velocity := linear_velocity
	var body_spin := angular_velocity
	var sub_dt := delta / float(SUBSTEPS)

	# Нагрузка и геометрия пятна за шаг не меняются — считаем один раз.
	var frames: Array[Array] = []
	for wheel: VehicleWheel in wheels:
		if not wheel.grounded:
			frames.append([])
			continue
		wheel.load = wheel.suspension_force() * suspension_health
		var normal := wheel.contact_normal
		var steer_basis := Basis(Vector3.UP, wheel.steer_angle)
		var wheel_forward := xform.basis * (steer_basis * Vector3.FORWARD)
		var forward := (wheel_forward - normal * wheel_forward.dot(normal))
		if forward.length_squared() < 1e-6:
			frames.append([])
			continue
		forward = forward.normalized()
		var right := normal.cross(forward).normalized()
		var arm := wheel.contact_point - com
		var contact_velocity := body_velocity + body_spin.cross(arm)
		frames.append([forward, right, normal, arm, contact_velocity])

		# Подвеска давит вдоль нормали — на склоне это даёт и подъёмную,
		# и боковую составляющую, ровно как в жизни.
		var suspension := normal * wheel.load
		total_force += suspension
		total_torque += arm.cross(suspension)

	for _step: int in SUBSTEPS:
		for i: int in wheels.size():
			var frame: Array = frames[i]
			if frame.is_empty():
				wheels[i].integrate_spin(sub_dt)
				continue
			var wheel := wheels[i]
			wheel.update_tire(frame[4], frame[0], frame[1], sub_dt, 1.0)
			wheel.integrate_spin(sub_dt)

			var longitudinal: float = wheel.force_longitudinal
			# Сопротивление качению и сгребание песка всегда против движения.
			var rolling := -signf(wheel.contact_speed_long) * wheel.resistance
			var force: Vector3 = frame[0] * (longitudinal + rolling) + frame[1] * wheel.force_lateral
			total_force += force / float(SUBSTEPS)
			total_torque += (frame[3] as Vector3).cross(force) / float(SUBSTEPS)

	for wheel: VehicleWheel in wheels:
		wheel.update_wear(delta)

	return [total_force, total_torque]


func _apply_accumulated(accumulated: Array, xform: Transform3D) -> void:
	var force: Vector3 = accumulated[0]
	var torque: Vector3 = accumulated[1]
	# Электронная стабилизация: гасит рыскание моментом вокруг вертикали.
	if Settings.assist_stability and speed > 4.0:
		var desired_yaw := forward_speed * tan(_steer_angle * config.steer_angle_max) / _wheelbase()
		var actual_yaw := angular_velocity.dot(xform.basis.y)
		var error := clampf(desired_yaw - actual_yaw, -1.2, 1.2)
		torque += xform.basis.y * error * mass * 0.9
	apply_central_force(force)
	apply_torque(torque)


func _apply_aero(xform: Transform3D) -> void:
	var relative := linear_velocity - wind_velocity
	var magnitude := relative.length()
	if magnitude < 0.05:
		return
	var direction := relative / magnitude
	var q := 0.5 * Config.air_density * magnitude * magnitude
	# Площадь считаем по проекции: лоб для продольного потока, борт для бокового.
	var forward_axis := -xform.basis.z
	var side_axis := xform.basis.x
	var frontal := absf(direction.dot(forward_axis)) * config.frontal_area
	var side := absf(direction.dot(side_axis)) * config.side_area
	var area := frontal + side
	var drag := -direction * q * config.drag_coefficient * area
	apply_central_force(drag)
	# Точка приложения выше центра масс — боковой ветер не только сносит, но и
	# кренит. Именно поэтому в бурю пустой фургон опаснее гружёного.
	apply_torque(xform.basis.y.cross(drag) * config.pressure_centre_height * 0.35)


func _fuel_starvation() -> float:
	if fuel > 1.5:
		return 1.0
	# На дне бака мотор начинает захлёбываться, а не глохнет разом.
	return clampf(fuel / 1.5, 0.0, 1.0)


func _consume_fuel(delta: float) -> void:
	if not drivetrain.running:
		return
	var used := drivetrain.fuel_used(delta)
	fuel = maxf(fuel - used, 0.0)
	if fuel <= 0.0:
		drivetrain.running = false
		EventBus.notify("Топливо кончилось", &"error")
	if player_controlled:
		GameState.stats["fuel_burned"] = float(GameState.stats.get("fuel_burned", 0.0)) + used


func _update_diagnostics(delta: float, velocity: Vector3) -> void:
	var travelled := velocity.length() * delta
	odometer += travelled
	_distance_since_sync += travelled
	if player_controlled and _distance_since_sync > 250.0:
		_distance_since_sync = 0.0
		GameState.stats["distance_driven"] = (
			float(GameState.stats.get("distance_driven", 0.0)) + 250.0
		)

	# Ударная перегрузка: разность скоростей за шаг, отфильтрованная, чтобы
	# мелкая тряска на гребёнке не считалась ударом.
	var acceleration := (velocity - _previous_velocity) / maxf(delta, 1e-5)
	_previous_velocity = velocity
	var g_force := acceleration.length() / Config.gravity
	_shock_filtered = maxf(_shock_filtered * 0.86, g_force)
	if _shock_filtered > Config.cargo_shock_threshold_g:
		_register_shock(_shock_filtered)
		_shock_filtered = 0.0

	var upright := global_transform.basis.y.dot(Vector3.UP)
	if upright < 0.25:
		_rollover_timer += delta
		if _rollover_timer > 1.2 and not rolled_over:
			rolled_over = true
			EventBus.notify("Машина на боку. R — вызвать эвакуатор", &"warning")
			if player_controlled:
				GameState.stats["rollovers"] = int(GameState.stats.get("rollovers", 0)) + 1
	else:
		_rollover_timer = 0.0
		rolled_over = false

	var digging := false
	for wheel: VehicleWheel in wheels:
		if wheel.is_digging():
			digging = true
	if speed < STUCK_SPEED and (command.throttle > 0.4 or digging):
		_stuck_timer += delta
	else:
		_stuck_timer = maxf(_stuck_timer - delta * 2.0, 0.0)
	var stuck_now := _stuck_timer > STUCK_TIME
	if stuck_now != is_stuck:
		is_stuck = stuck_now
		EventBus.vehicle_stuck_changed.emit(is_stuck)

	_publish_telemetry()


## Удар: бьёт кузов и груз. Хрупкое стекло на трамплине — это не «минус
## сколько-то очков», а конкретный процент от гонорара.
func _register_shock(g_force: float) -> void:
	var excess := g_force - Config.cargo_shock_threshold_g
	body_health = clampf(body_health - excess * 0.004, 0.0, 1.0)
	suspension_health = clampf(suspension_health - excess * 0.006, 0.0, 1.0)
	EventBus.vehicle_impact.emit(excess, global_position)
	if not player_controlled:
		return
	for contract: Contract in GameState.active_contracts():
		var cargo := contract.cargo()
		if cargo == null:
			continue
		contract.apply_damage(excess * Config.cargo_shock_scale * cargo.fragility)


func _publish_telemetry() -> void:
	if not player_controlled:
		return
	Telemetry.set_scalar(&"speed", speed)
	Telemetry.set_scalar(&"rpm", drivetrain.rpm())
	Telemetry.set_scalar(&"gear", float(drivetrain.gear))
	Telemetry.set_scalar(&"fuel", fuel)
	Telemetry.set_scalar(&"coolant", drivetrain.coolant_temp)
	Telemetry.set_scalar(&"clutch", drivetrain.clutch_engagement)
	var load := 0.0
	var sink := 0.0
	for wheel: VehicleWheel in wheels:
		load += wheel.load
		sink = maxf(sink, wheel.sinkage)
	Telemetry.set_scalar(&"load", load)
	Telemetry.set_scalar(&"sinkage", sink)
	telemetry_updated.emit()


func _update_visuals(delta: float) -> void:
	for i: int in mini(_wheel_visuals.size(), wheels.size()):
		var node := _wheel_visuals[i]
		if node == null:
			continue
		var wheel := wheels[i]
		node.transform = Transform3D(
			Basis(Vector3.UP, wheel.steer_angle) * Basis(Vector3.RIGHT, -wheel.spin_angle),
			to_local(wheel.wheel_centre) if wheel.grounded else _hanging_centre(wheel)
		)


func _hanging_centre(wheel: VehicleWheel) -> Vector3:
	return wheel.spec.position - Vector3.UP * (wheel.max_ray_length() - wheel.spec.radius)


# --- Действия игрока -------------------------------------------------------

func adjust_pressure(delta_bar: float) -> void:
	if speed > 1.0:
		EventBus.notify("Давление меняют на стоянке", &"warning")
		return
	for wheel: VehicleWheel in wheels:
		wheel.set_pressure(wheel.pressure + delta_bar)
	EventBus.notify("Давление в шинах: %.1f бар" % wheels[0].pressure)


func set_pressure_all(value: float) -> void:
	for wheel: VehicleWheel in wheels:
		wheel.set_pressure(value)


func refuel(litres: float) -> float:
	var added := minf(litres, config.fuel_capacity - fuel)
	fuel += added
	if added > 0.0 and not drivetrain.running:
		drivetrain.running = true
		drivetrain.engine_omega = Drivetrain.rpm_to_omega(config.idle_rpm)
	return added


func repair(component: StringName, amount: float) -> void:
	match component:
		&"engine":
			engine_health = clampf(engine_health + amount, 0.0, 1.0)
			drivetrain.health = engine_health
			drivetrain.coolant_temp = Drivetrain.AMBIENT_TEMP
		&"body":
			body_health = clampf(body_health + amount, 0.0, 1.0)
		&"suspension":
			suspension_health = clampf(suspension_health + amount, 0.0, 1.0)
		&"tires":
			for wheel: VehicleWheel in wheels:
				wheel.wear = maxf(wheel.wear - amount, 0.0)


## Эвакуатор: ставит машину на колёса рядом с местом происшествия. Стоит
## времени и денег — иначе кнопка R превращается в чит.
func request_recovery() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 40.0
	var to := global_position - Vector3.UP * 60.0
	var query := PhysicsRayQueryParameters3D.create(from, to, ground_mask, [get_rid()])
	var hit := space.intersect_ray(query)
	var ground := hit.get("position", global_position) as Vector3

	var heading := -global_transform.basis.z
	heading.y = 0.0
	if heading.length_squared() < 0.01:
		heading = Vector3.FORWARD
	var basis := Basis.looking_at(heading.normalized(), Vector3.UP)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(basis, ground + Vector3.UP * (config.rest_length + 0.55))
	rolled_over = false
	_stuck_timer = 0.0
	if player_controlled:
		GameState.advance_time(0.5)
		GameState.add_money(-180.0)
		EventBus.notify("Эвакуатор: −180 дх, полчаса", &"warning")


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Контакты читаем здесь: только состояние тела знает реальные импульсы удара.
	for i: int in state.get_contact_count():
		var impulse := state.get_contact_impulse(i)
		var severity := impulse.length() / maxf(mass, 1.0)
		if severity > 1.4:
			body_health = clampf(body_health - severity * 0.0025, 0.0, 1.0)
			EventBus.vehicle_impact.emit(severity, state.get_contact_local_position(i))
