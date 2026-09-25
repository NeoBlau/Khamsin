class_name VehicleWheel
extends RefCounted
## Одно колесо: подвеска, пятно контакта, шина.
##
## Не узел сцены — узлов ровно столько, сколько нужно для картинки, а вся
## механика живёт в обычных объектах. Так проще гонять её в тестах без сцены.

## Постоянная времени фильтра просадки, секунды. Смысл — сколько песок
## «догоняет» изменившуюся нагрузку. Меньше — и удар снова штампует яму,
## больше — и стоящая машина слишком долго не садится в грунт.
const SINKAGE_SETTLE_TAU := 0.33

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
## Множитель сцепления от температуры — для приборов и телеметрии.
var grip_from_heat: float = 1.0
## Развал колеса, радианы. Отрицательный — верх колеса к машине.
var camber: float = 0.0
## Просадка, отфильтрованная по времени, метры.
##
## В грунт пишется она, а не мгновенная. Причина физическая: пластическая
## деформация идёт за длительной нагрузкой, а не за пиком. Удар при приземлении
## длится миллисекунды, и формула просадки выдаёт на нём полметра — но песок
## за это время столько материала в стороны не вытеснит.
##
## Без фильтра это ловится сразу: машина, упавшая с четырёх метров, штампует
## под собой яму предельной глубины, два колеса повисают в воздухе, и дальше
## она никуда не едет. Постоянная времени — треть секунды.
var sinkage_settled: float = 0.0
## Рыхлость песка под колесом, 0..1. Своя же колея, разрытая буксованием,
## возвращается сюда следующим проходом и топит колесо глубже.
var ground_looseness: float = 0.0
## Насколько колесо просело в чужой или свой след, метры. Для звука и пыли.
var track_offset: float = 0.0
## Стабилизирующий момент вокруг нормали к грунту, Н·м.
var aligning_moment: float = 0.0
## Температура тормозного механизма, °C. Своя у каждого колеса: передние
## греются сильнее, и именно они отказывают первыми.
var brake_temperature: float = 35.0



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
		sinkage_settled = 0.0
		compression_velocity = (compression - previous_compression) / maxf(dt, 1e-5)
		wheel_centre = mount - up * (max_ray_length() - spec.radius)
		contact_normal = up
		sinkage = 0.0
		return false

	contact_point = hit["position"]
	contact_normal = (hit["normal"] as Vector3).normalized()
	# Колея. Коллизия рельефа остаётся гладкой — перестраивать её каждый кадр
	# нельзя, — но точка контакта опускается на поправку от продавленного
	# песка. Для подвески это неотличимо от настоящей ямы: она и есть настоящая
	# яма, просто записанная не в меше, а в сетке поправок.
	track_offset = World.sand.offset(contact_point.x, contact_point.z)
	ground_looseness = World.sand.looseness(contact_point.x, contact_point.z)
	# Ограничение не косметическое: между колеёй под одним колесом и бруствером
	# под соседним набирается перекос, и без потолка машина встаёт на два
	# колеса там, где в жизни просто качнулась бы.
	track_offset = clampf(track_offset, -SandField.MAX_DEPTH, SandField.MAX_DEPTH * 0.5)
	if absf(track_offset) > 0.0005:
		contact_point.y += track_offset
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
		aligning_moment = 0.0
		slip_ratio = TireModel.relax(slip_ratio, 0.0, 1.0, config.relaxation_length, dt)
		slip_angle = TireModel.relax(slip_angle, 0.0, 1.0, config.relaxation_length, dt)
		return

	contact_speed_long = velocity.dot(forward)
	contact_speed_lat = velocity.dot(right)

	patch_area = TireModel.patch_area(load, pressure, spec.width, spec.radius)
	# Глубже половины радиуса колесо не уходит: дальше в грунт упирается мост, и
	# это уже не качение, а сидение на брюхе. Без ограничения формула на
	# предельных нагрузках выдаёт метровую просадку, и машина встаёт намертво.
	# Взрыхлённый песок держит хуже слежавшегося: там, где уже прошло колесо,
	# зёрна не упакованы, и следующий проход уходит глубже. Из-за этого второй
	# круг по своей колее тяжелее первого, а буксование на месте роет яму.
	var loose_sink := 1.0 + ground_looseness * 0.30
	sinkage = minf(
		TireModel.sinkage(surface, load, patch_area) * loose_sink, spec.radius * 0.75
	)
	sinkage_settled += (sinkage - sinkage_settled) * (1.0 - exp(-dt / SINKAGE_SETTLE_TAU))

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
	# Температура резины. В пустыне это не тонкость: долгий перегон на
	# скорости выводит шины за сотню градусов, и машина начинает плыть на
	# ровном месте, хотя ни нагрузка, ни покрытие, ни износ не поменялись.
	grip_from_heat = TireModel.temperature_factor(temperature)
	mu *= grip_from_heat
	# Рыхлый песок не держит. Коэффициент небольшой намеренно: сцепление здесь
	# теряется в основном через просадку и сопротивление, а не напрямую, и
	# если сделать штраф крупным, машина начинает срываться на ровном месте.
	mu *= 1.0 - ground_looseness * 0.22

	# Развал от хода подвески. Знак зеркальный по бортам: у левого и правого
	# колеса верх наклоняется в противоположные стороны относительно оси
	# машины. Без зеркала тяга от развала на обоих колёсах смотрит в одну
	# сторону, и машину на прямой постоянно сносит вбок — при том что ни руль,
	# ни ветер, ни уклон тут ни при чём.
	var side := signf(spec.position.x)
	camber = TireModel.camber_from_travel(compression, config.suspension_travel) * side

	var forces := TireModel.forces(
		slip_ratio, slip_angle, load, mu, config.kappa_peak, config.alpha_peak
	)
	force_longitudinal = forces.x
	force_lateral = forces.y + TireModel.camber_thrust(camber, load, mu)
	aligning_moment = TireModel.aligning_moment(
		slip_angle,
		force_lateral,
		TireModel.patch_length(load, pressure, spec.width, spec.radius)
	)
	resistance = TireModel.motion_resistance(surface, load, sinkage, pressure)
	_leave_track(dt, velocity)


## Пишет след в песок. Глубина — та, на которую колесо реально просело;
## рыхлость — от проскальзывания: катящееся колесо уплотняет песок под собой,
## буксующее его перелопачивает, и разница между этими двумя случаями и есть
## разница между «проехал» и «закопался».
func _leave_track(dt: float, velocity: Vector3) -> void:
	var softness := surface.softness()
	if softness <= 0.01 or sinkage_settled <= 0.002:
		return
	var churn := clampf(absf(slip_ratio) * 0.55 + absf(slip_angle) * 0.5, 0.0, 1.0)
	var packing := clampf(absf(contact_speed_long) * 0.08, 0.0, 1.0)
	var loose := clampf(0.12 + churn - packing * 0.1, 0.0, 1.0)
	# Стоящее колесо не должно бесконечно углублять одну ячейку: в carve
	# глубина берётся максимумом, но рыхлость копится, и без учёта времени
	# машина на стоянке за минуту ушла бы по мосты.
	var rate := clampf(dt * 60.0, 0.0, 1.0)
	# Рыхлость не переливается сама в себя: если добавлять к новой старую,
	# получается копилка, из которой она уже не убывает, и песок под стоящей
	# машиной вечно «свежевзрыхлённый».
	# Грунт перемещает только работающее колесо — и в этом вся тонкость.
	#
	# Стоящее колесо песок под собой уминает, но колею не роет: равновесие,
	# на котором оно стоит, уже посчитано в sinkage и уже учтено в радиусе
	# качения. Записать его ещё и в грунт — значит посчитать одну и ту же
	# просадку дважды, и тогда машина, простоявшая минуту на рыхлом песке,
	# оказывается в яме по ступицы и не трогается вовсе. Ровно это и
	# случилось: тест про спущенные колёса показал ноль метров в секунду.
	#
	# Работает колесо в двух случаях: катится по новому грунту или срезает
	# его на месте буксованием. Второе важно не меньше первого — именно так
	# закапываются, и именно это должно оставлять яму.
	var rolling := absf(contact_speed_long)
	var shearing := absf(slip_ratio) * maxf(rolling, TireModel.CREEP_SPEED)
	var plough := clampf(maxf(rolling, shearing) / 2.5, 0.0, 1.0)
	# Направление хода нужно, чтобы бруствер ложился вбок и назад, а не под
	# колесо, которому ещё ехать. Берётся от скорости пятна контакта в плане.
	var along := Vector2(velocity.x, velocity.z)
	World.sand.carve(
		contact_point,
		spec.width,
		sinkage_settled,
		loose * rate,
		softness,
		plough,
		along.normalized() if along.length() > 0.2 else Vector2.ZERO
	)


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


## Нагрев и остывание тормозов.
##
## Тепло — это работа трения: момент на угловой скорости. Остывание
## пропорционально перегреву и обдуву, поэтому стоящая машина остывает в разы
## медленнее едущей — и на светофоре после длинного спуска тормоза продолжают
## слабеть, хотя ими уже не пользуются.
func update_brake_heat(applied_torque: float, dt: float) -> void:
	var work := absf(applied_torque * angular_velocity)
	# Теплоёмкость всего механизма, Дж/К. Число грубое, но порядок верный:
	# чугунный диск грузовика — это несколько килограммов металла.
	var heat_capacity := 14000.0
	var airflow := 22.0 + absf(contact_speed_long) * 9.0
	var cooling := (brake_temperature - 35.0) * airflow
	brake_temperature = clampf(
		brake_temperature + (work - cooling) / heat_capacity * dt, 10.0, 900.0
	)
