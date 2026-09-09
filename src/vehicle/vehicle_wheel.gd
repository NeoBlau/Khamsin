class_name VehicleWheel
extends RefCounted
## Одно колесо: подвеска, пятно контакта, шина.
##
## Не узел сцены — узлов ровно столько, сколько нужно для картинки, а вся
## механика живёт в обычных объектах. Так проще гонять её в тестах без сцены.

var spec: VehicleConfig.WheelSpec
var config: VehicleConfig

# --- Геометрия и состояние подвески ----------------------------------------

var steer_angle: float = 0.0
## Текущее сжатие подвески от полностью разжатой, метры.
var compression: float = 0.0
var previous_compression: float = 0.0
var compression_velocity: float = 0.0
var grounded: bool = false
var contact_point: Vector3 = Vector3.ZERO
var contact_normal: Vector3 = Vector3.UP
var wheel_centre: Vector3 = Vector3.ZERO

# --- Нагрузка и силы -------------------------------------------------------

var load: float = 0.0
## Добавка от стабилизатора поперечной устойчивости, Н.
var antiroll_force: float = 0.0
var force_longitudinal: float = 0.0
var force_lateral: float = 0.0
var resistance: float = 0.0

# --- Вращение и скольжение -------------------------------------------------

var angular_velocity: float = 0.0
var spin_angle: float = 0.0
var drive_torque: float = 0.0
## Инерция двигателя и трансмиссии, приведённая к этому колесу. Ставится
## трансмиссией каждый шаг: она зависит от передачи и от того, замкнуто ли
## сцепление.
var coupled_inertia: float = 0.0
var brake_torque: float = 0.0
var slip_ratio: float = 0.0
var slip_angle: float = 0.0
var contact_speed_long: float = 0.0
var contact_speed_lat: float = 0.0

# --- Грунт и резина --------------------------------------------------------

var surface: Surface = null
var sinkage: float = 0.0
var patch_area: float = 0.0
var pressure: float = 2.4
var wear: float = 0.0
var temperature: float = 30.0

var _last_position: Vector3 = Vector3.ZERO
var _has_last_position: bool = false


func setup(wheel_spec: VehicleConfig.WheelSpec, vehicle_config: VehicleConfig) -> void:
	spec = wheel_spec
	config = vehicle_config
	pressure = vehicle_config.pressure_nominal
	surface = Surface.default_surface()
	compression = 0.0
	previous_compression = 0.0


## Полная длина луча подвески от точки крепления до земли при полном отбое.
func max_ray_length() -> float:
	return config.rest_length + spec.radius


## Ищет землю под колесом и обновляет геометрию подвески.
##
## Возвращает true, если колесо коснулось. `body_rid` исключается из проверки,
## иначе луч упрётся в собственную коллизию кузова.
func probe(
	space: PhysicsDirectSpaceState3D,
	body_transform: Transform3D,
	body_rid: RID,
	collision_mask: int,
	dt: float
) -> bool:
	previous_compression = compression
	var up := body_transform.basis.y
	var mount := body_transform * spec.position
	var query := PhysicsRayQueryParameters3D.create(
		mount + up * 0.10, mount - up * max_ray_length(), collision_mask, [body_rid]
	)
	query.hit_back_faces = false
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		grounded = false
		load = 0.0
		# Колесо в воздухе — подвеска распрямляется, но не рывком.
		compression = maxf(compression - 6.0 * dt, 0.0)
		compression_velocity = (compression - previous_compression) / maxf(dt, 1e-5)
		wheel_centre = mount - up * (max_ray_length() - spec.radius)
		contact_normal = up
		sinkage = 0.0
		return false

	contact_point = hit["position"]
	contact_normal = (hit["normal"] as Vector3).normalized()
	# Расстояние меряем от точки крепления, а не от начала луча.
	var distance := (mount - contact_point).dot(up)
	compression = clampf(
		max_ray_length() - distance, 0.0, config.suspension_travel + config.rest_length
	)
	compression_velocity = (compression - previous_compression) / maxf(dt, 1e-5)
	wheel_centre = mount - up * (distance - spec.radius)
	grounded = true
	return true


## Сила подвески вдоль оси стойки, Н. Отрицательной не бывает: пружина умеет
## только толкать.
func suspension_force() -> float:
	if not grounded:
		return 0.0
	var travel := config.suspension_travel
	var spring := config.spring_rate * compression
	# Отбойник в последней четверти хода. Без него на трамплине подвеска
	# «протыкает» кузов сквозь землю.
	var over := compression - travel * 0.85
	if over > 0.0:
		spring += config.bump_stop_rate * over * over / maxf(travel * 0.15, 0.01)
	var damping := (
		config.damper_bump if compression_velocity > 0.0 else config.damper_rebound
	)
	var damper := damping * compression_velocity
	return maxf(spring + damper + antiroll_force, 0.0)


## Пересчитывает скольжение, сцепление и силы в пятне контакта.
##
## `velocity` — скорость точки контакта в мировых координатах,
## `forward`/`right` — оси пятна с уже учтённым поворотом колеса.
func update_tire(
	velocity: Vector3, forward: Vector3, right: Vector3, dt: float, mu_scale: float
) -> void:
	if not grounded or load <= 0.0:
		force_longitudinal = 0.0
		force_lateral = 0.0
		resistance = 0.0
		slip_ratio = TireModel.relax(slip_ratio, 0.0, 1.0, config.relaxation_length, dt)
		slip_angle = TireModel.relax(slip_angle, 0.0, 1.0, config.relaxation_length, dt)
		return

	contact_speed_long = velocity.dot(forward)
	contact_speed_lat = velocity.dot(right)

	patch_area = TireModel.patch_area(load, pressure, spec.width, spec.radius)
	# Глубже половины радиуса колесо не уходит: дальше в грунт упирается мост, и
	# это уже не качение, а сидение на брюхе. Без ограничения формула на
	# предельных нагрузках выдаёт метровую просадку, и машина встаёт намертво.
	sinkage = minf(TireModel.sinkage(surface, load, patch_area), spec.radius * 0.75)

	var wheel_speed := angular_velocity * rolling_radius()
	var reference := maxf(absf(contact_speed_long), TireModel.CREEP_SPEED)

	var target_kappa := clampf((wheel_speed - contact_speed_long) / reference, -8.0, 8.0)
	var target_alpha := atan2(contact_speed_lat, reference)

	var speed := absf(contact_speed_long)
	slip_ratio = TireModel.relax(slip_ratio, target_kappa, speed, config.relaxation_length, dt)
	slip_angle = TireModel.relax(slip_angle, target_alpha, speed, config.relaxation_length, dt)

	var mu := TireModel.effective_mu(
		config.tire_mu, surface.grip, load, config.nominal_load, config.load_sensitivity, wear
	)
	mu *= mu_scale

	var forces := TireModel.forces(
		slip_ratio, slip_angle, load, mu, config.kappa_peak, config.alpha_peak
	)
	force_longitudinal = forces.x
	force_lateral = forces.y
	resistance = TireModel.motion_resistance(surface, load, sinkage, pressure)


## Эффективный радиус качения: меньше номинального на прогиб шины и на
## половину просадки в грунт. По нему считается и скольжение, и передаточное
## отношение «обороты — скорость», поэтому он обязан быть один на всех.
func rolling_radius() -> float:
	return maxf(spec.radius - sinkage * 0.5 - _deflection(), spec.radius * 0.6)


## Прогиб шины под нагрузкой, метры. Отдельной функцией — им пользуется и
## визуализация, чтобы колесо на месте не висело над землёй.
func _deflection() -> float:
	return TireModel.deflection(load, pressure, config.pressure_nominal, spec.radius)


## Крутит колесо и возвращает продольную силу, которая уйдёт в кузов.
##
## Здесь же ловится блокировка: если тормозного момента хватает, чтобы
## остановить колесо за шаг, колесо просто останавливают, а не разгоняют назад.
func integrate_spin(dt: float) -> void:
	var radius := rolling_radius()
	var reaction := -force_longitudinal * radius
	var resist := -signf(angular_velocity) * resistance * radius * 0.5
	var net := drive_torque + reaction + resist

	var brake := brake_torque
	if brake > 0.0:
		var stopping := brake * signf(angular_velocity)
		var predicted := angular_velocity + (net - stopping) / rotational_inertia() * dt
		if signf(predicted) != signf(angular_velocity) and absf(angular_velocity) > 1e-4:
			# Тормоз пересилил — колесо встаёт, а не начинает крутиться назад.
			angular_velocity = 0.0
			return
		net -= stopping

	angular_velocity += net / rotational_inertia() * dt
	spin_angle = fposmod(spin_angle + angular_velocity * dt, TAU)


## Инерция, которую колесо разгоняет вместе с собой.
##
## Без приведённой инерции двигателя это самая опасная строчка в модели. На
## первой передаче отношение около двадцати пяти к одному, и момент сцепления
## приходит на колесо умноженным на двадцать пять. Если раскручивать при этом
## одно только колесо, петля «колесо крутанулось — вал обогнал двигатель —
## сцепление сменило знак» получает огромный коэффициент усиления, и колёса
## начинают вращаться назад при полном газе вперёд. Приведённая инерция гасит
## это и физически верна: маховик на первой передаче ощущается со стороны
## колеса примерно в шестьсот раз тяжелее, чем есть.
func rotational_inertia() -> float:
	return maxf(spec.inertia + coupled_inertia, 0.01)


## Износ и нагрев резины от проскальзывания. Считается раз в кадр, не в подшаге.
func update_wear(dt: float) -> void:
	var slip_speed := absf(slip_ratio * maxf(absf(contact_speed_long), 1.0))
	slip_speed += absf(contact_speed_lat)
	var work := slip_speed * load * 1e-7
	# На камне резина стирается быстрее, чем на песке при том же скольжении.
	wear = clampf(wear + work * dt * (0.4 + surface.grip), 0.0, 1.0)
	var heat := work * 45.0
	var cooling := (temperature - 35.0) * (0.12 + absf(contact_speed_long) * 0.01)
	temperature = clampf(temperature + (heat - cooling) * dt, 10.0, 160.0)


func set_pressure(value: float) -> void:
	pressure = clampf(value, config.pressure_min, config.pressure_max)


## Колесо считается закопавшимся, если оно буксует, а машина стоит.
func is_digging() -> bool:
	return (
		grounded
		and surface.diggable
		and absf(slip_ratio) > 1.5
		and absf(contact_speed_long) < 1.2
	)
