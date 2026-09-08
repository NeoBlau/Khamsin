class_name VehicleConfig
extends Resource
## Полное описание машины. Всё, что можно покрутить, лежит здесь и грузится из
## `res://data/vehicles/*.json` — код машины не содержит ни одного магического
## числа, иначе балансировать пришлось бы пересборкой.

class WheelSpec extends RefCounted:
	## Положение ступицы в системе кузова, метры. X вправо, Y вверх, Z назад.
	var position: Vector3 = Vector3.ZERO
	var steered: bool = false
	var driven: bool = true
	var handbrake: bool = false
	var radius: float = 0.42
	var width: float = 0.28
	## Момент инерции колеса в сборе, кг·м². Для 35" колеса грузовика ~2.
	var inertia: float = 2.1
	## Доля общего тормозного момента.
	var brake_bias: float = 0.5


@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var price: float = 0.0

# --- Кузов -----------------------------------------------------------------

## Снаряжённая масса без топлива и груза, кг.
@export var mass: float = 3200.0
## Центр масс относительно начала координат кузова.
@export var center_of_mass: Vector3 = Vector3(0.0, -0.25, 0.05)
## Габариты кузова для меша и коллизии: ширина, высота, длина.
@export var body_size: Vector3 = Vector3(2.1, 1.35, 5.4)
## Смещение центра коробки кузова относительно начала координат. Начало
## координат совпадает с точками крепления подвески, поэтому кузов приходится
## поднимать — иначе он окажется в земле.
@export var body_offset: Vector3 = Vector3(0.0, 0.25, 0.0)
## Моменты инерции вокруг осей X, Y, Z. Ноль — считать из формы.
@export var inertia: Vector3 = Vector3(4200.0, 5600.0, 1500.0)

# --- Колёса и подвеска -----------------------------------------------------

var wheels: Array[WheelSpec] = []

## Жёсткость пружины, Н/м. Для 6-тонника ~90 000 на колесо.
@export var spring_rate: float = 92000.0
@export var damper_bump: float = 7400.0
@export var damper_rebound: float = 11000.0
## Ход подвески от полного отбоя до полного сжатия, метры.
@export var suspension_travel: float = 0.30
## Длина пружины без нагрузки, метры.
@export var rest_length: float = 0.38
## Жёсткость отбойника в конце хода, Н/м. Он и ловит пробои на трамплинах.
@export var bump_stop_rate: float = 620000.0
@export var antiroll_front: float = 22000.0
@export var antiroll_rear: float = 16000.0

# --- Шины ------------------------------------------------------------------

## Пиковый коэффициент сцепления на эталонном покрытии (укатанный грунт).
@export var tire_mu: float = 1.05
## Проскальзывание, при котором продольная сила максимальна.
@export var kappa_peak: float = 0.13
## Угол увода пика боковой силы, радианы (~7.5°).
@export var alpha_peak: float = 0.13
## Насколько падает сцепление с ростом нагрузки. 0 — идеальная шина.
@export var load_sensitivity: float = 0.22
## Нормальная нагрузка, к которой отнесена load_sensitivity, Н.
@export var nominal_load: float = 9000.0
## Длина релаксации каркаса, метры. Убирает сингулярность на нулевой скорости.
@export var relaxation_length: float = 0.35
@export var pressure_min: float = 0.8
@export var pressure_max: float = 3.2
@export var pressure_nominal: float = 2.4

# --- Двигатель -------------------------------------------------------------

@export var idle_rpm: float = 700.0
@export var max_rpm: float = 4200.0
@export var redline_rpm: float = 3900.0
## Кривая момента: пары [об/мин, Н·м], отсортированные по оборотам.
@export var torque_curve: PackedVector2Array = PackedVector2Array()
## Момент инерции коленвала с маховиком, кг·м².
@export var engine_inertia: float = 0.62
## Момент трения на холостых, Н·м.
@export var engine_friction: float = 26.0
## Удельный расход, г/(кВт·ч). Хороший дизель — 200-230.
@export var bsfc: float = 214.0
## Плотность топлива, кг/л.
@export var fuel_density: float = 0.835
@export var fuel_capacity: float = 160.0
## Мощность, уходящая в тепло при полной нагрузке, кВт.
@export var cooling_capacity: float = 48.0
@export var thermal_mass: float = 34.0

# --- Трансмиссия -----------------------------------------------------------

@export var gear_ratios: PackedFloat32Array = PackedFloat32Array([4.7, 2.6, 1.62, 1.16, 0.87, 0.7])
@export var reverse_ratio: float = 4.2
@export var final_drive: float = 4.3
@export var transfer_high: float = 1.0
@export var transfer_low: float = 2.72
@export var driveline_efficiency: float = 0.9
## Момент, который держит сцепление до пробуксовки, Н·м.
@export var clutch_capacity: float = 1400.0
@export var shift_time: float = 0.35
## Инерция вращающихся частей трансмиссии, приведённая ко входу КПП, кг·м².
@export var driveline_inertia: float = 0.14
## Коэффициент блокировки дифференциала: 0 — свободный, 1 — жёсткая ось.
@export var diff_lock_open: float = 0.12
@export var diff_lock_locked: float = 0.95

# --- Тормоза ---------------------------------------------------------------

@export var brake_torque: float = 5200.0
@export var handbrake_torque: float = 3400.0

# --- Аэродинамика ----------------------------------------------------------

@export var drag_coefficient: float = 0.62
@export var frontal_area: float = 4.1
## Площадь борта — по ней ветер сдувает машину боком в бурю.
@export var side_area: float = 9.4
## Высота центра парусности над центром масс, метры.
@export var pressure_centre_height: float = 0.55

# --- Кузов под груз --------------------------------------------------------

@export var cargo_mass_limit: float = 6000.0
@export var cargo_volume_limit: float = 22.0
@export var steer_angle_max: float = 0.62
## Во сколько раз уменьшается максимальный угол на 30 м/с — иначе руль на
## скорости становится оружием против самого себя.
@export var steer_speed_falloff: float = 0.62


func driven_wheel_count() -> int:
	var count := 0
	for w: WheelSpec in wheels:
		if w.driven:
			count += 1
	return count


## Момент двигателя при заданных оборотах, линейная интерполяция кривой.
func torque_at(rpm: float) -> float:
	if torque_curve.is_empty():
		return 0.0
	if rpm <= torque_curve[0].x:
		return torque_curve[0].y
	var last := torque_curve.size() - 1
	if rpm >= torque_curve[last].x:
		return torque_curve[last].y
	for i: int in range(1, torque_curve.size()):
		var b := torque_curve[i]
		if rpm <= b.x:
			var a := torque_curve[i - 1]
			var t := (rpm - a.x) / maxf(b.x - a.x, 0.001)
			return lerpf(a.y, b.y, t)
	return torque_curve[last].y


func peak_torque() -> float:
	var best := 0.0
	for point: Vector2 in torque_curve:
		best = maxf(best, point.y)
	return best


## Максимальная мощность в кВт и обороты, на которых она достигается.
func peak_power() -> Vector2:
	var best_kw := 0.0
	var best_rpm := 0.0
	var rpm := idle_rpm
	while rpm <= max_rpm:
		var kw := torque_at(rpm) * rpm * TAU / 60.0 / 1000.0
		if kw > best_kw:
			best_kw = kw
			best_rpm = rpm
		rpm += 25.0
	return Vector2(best_kw, best_rpm)


func gear_ratio(gear: int) -> float:
	## gear: -1 задняя, 0 нейтраль, 1..n передачи.
	if gear < 0:
		return -reverse_ratio
	if gear == 0:
		return 0.0
	return gear_ratios[clampi(gear - 1, 0, gear_ratios.size() - 1)]


func top_gear() -> int:
	return gear_ratios.size()


static func from_dict(data: Dictionary) -> VehicleConfig:
	var c := VehicleConfig.new()
	c.id = StringName(data.get("id", ""))
	c.display_name = String(data.get("name", data.get("id", "")))
	c.description = String(data.get("description", ""))
	c.price = float(data.get("price", 0.0))

	var body: Dictionary = data.get("body", {})
	c.mass = float(body.get("mass", c.mass))
	c.center_of_mass = _vec3(body.get("center_of_mass"), c.center_of_mass)
	c.body_size = _vec3(body.get("size"), c.body_size)
	c.body_offset = _vec3(body.get("offset"), c.body_offset)
	c.inertia = _vec3(body.get("inertia"), c.inertia)
	c.cargo_mass_limit = float(body.get("cargo_mass_limit", c.cargo_mass_limit))
	c.cargo_volume_limit = float(body.get("cargo_volume_limit", c.cargo_volume_limit))

	var susp: Dictionary = data.get("suspension", {})
	c.spring_rate = float(susp.get("spring_rate", c.spring_rate))
	c.damper_bump = float(susp.get("damper_bump", c.damper_bump))
	c.damper_rebound = float(susp.get("damper_rebound", c.damper_rebound))
	c.suspension_travel = float(susp.get("travel", c.suspension_travel))
	c.rest_length = float(susp.get("rest_length", c.rest_length))
	c.bump_stop_rate = float(susp.get("bump_stop_rate", c.bump_stop_rate))
	c.antiroll_front = float(susp.get("antiroll_front", c.antiroll_front))
	c.antiroll_rear = float(susp.get("antiroll_rear", c.antiroll_rear))

	var tire: Dictionary = data.get("tire", {})
	c.tire_mu = float(tire.get("mu", c.tire_mu))
	c.kappa_peak = float(tire.get("kappa_peak", c.kappa_peak))
	c.alpha_peak = float(tire.get("alpha_peak", c.alpha_peak))
	c.load_sensitivity = float(tire.get("load_sensitivity", c.load_sensitivity))
	c.nominal_load = float(tire.get("nominal_load", c.nominal_load))
	c.relaxation_length = float(tire.get("relaxation_length", c.relaxation_length))
	c.pressure_min = float(tire.get("pressure_min", c.pressure_min))
	c.pressure_max = float(tire.get("pressure_max", c.pressure_max))
	c.pressure_nominal = float(tire.get("pressure_nominal", c.pressure_nominal))

	var engine: Dictionary = data.get("engine", {})
	c.idle_rpm = float(engine.get("idle_rpm", c.idle_rpm))
	c.max_rpm = float(engine.get("max_rpm", c.max_rpm))
	c.redline_rpm = float(engine.get("redline_rpm", c.redline_rpm))
	c.engine_inertia = float(engine.get("inertia", c.engine_inertia))
	c.engine_friction = float(engine.get("friction", c.engine_friction))
	c.bsfc = float(engine.get("bsfc", c.bsfc))
	c.fuel_density = float(engine.get("fuel_density", c.fuel_density))
	c.fuel_capacity = float(engine.get("fuel_capacity", c.fuel_capacity))
	c.cooling_capacity = float(engine.get("cooling_capacity", c.cooling_capacity))
	c.thermal_mass = float(engine.get("thermal_mass", c.thermal_mass))
	var curve := PackedVector2Array()
	for point: Variant in engine.get("torque_curve", []):
		if typeof(point) == TYPE_ARRAY and (point as Array).size() >= 2:
			curve.append(Vector2(float(point[0]), float(point[1])))
	if not curve.is_empty():
		c.torque_curve = curve

	var trans: Dictionary = data.get("transmission", {})
	var ratios := PackedFloat32Array()
	for value: Variant in trans.get("gears", []):
		ratios.append(float(value))
	if not ratios.is_empty():
		c.gear_ratios = ratios
	c.reverse_ratio = float(trans.get("reverse", c.reverse_ratio))
	c.final_drive = float(trans.get("final_drive", c.final_drive))
	c.transfer_high = float(trans.get("transfer_high", c.transfer_high))
	c.transfer_low = float(trans.get("transfer_low", c.transfer_low))
	c.driveline_efficiency = float(trans.get("efficiency", c.driveline_efficiency))
	c.clutch_capacity = float(trans.get("clutch_capacity", c.clutch_capacity))
	c.shift_time = float(trans.get("shift_time", c.shift_time))
	c.driveline_inertia = float(trans.get("inertia", c.driveline_inertia))
	c.diff_lock_open = float(trans.get("diff_lock_open", c.diff_lock_open))
	c.diff_lock_locked = float(trans.get("diff_lock_locked", c.diff_lock_locked))

	var brakes: Dictionary = data.get("brakes", {})
	c.brake_torque = float(brakes.get("service", c.brake_torque))
	c.handbrake_torque = float(brakes.get("handbrake", c.handbrake_torque))

	var aero: Dictionary = data.get("aero", {})
	c.drag_coefficient = float(aero.get("cd", c.drag_coefficient))
	c.frontal_area = float(aero.get("frontal_area", c.frontal_area))
	c.side_area = float(aero.get("side_area", c.side_area))
	c.pressure_centre_height = float(aero.get("pressure_centre_height", c.pressure_centre_height))

	var steering: Dictionary = data.get("steering", {})
	c.steer_angle_max = float(steering.get("max_angle", c.steer_angle_max))
	c.steer_speed_falloff = float(steering.get("speed_falloff", c.steer_speed_falloff))

	c.wheels = []
	for entry: Variant in data.get("wheels", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var spec := WheelSpec.new()
		var w := entry as Dictionary
		spec.position = _vec3(w.get("position"), Vector3.ZERO)
		spec.steered = bool(w.get("steered", false))
		spec.driven = bool(w.get("driven", true))
		spec.handbrake = bool(w.get("handbrake", false))
		spec.radius = float(w.get("radius", 0.42))
		spec.width = float(w.get("width", 0.28))
		spec.inertia = float(w.get("inertia", 2.1))
		spec.brake_bias = float(w.get("brake_bias", 0.5))
		c.wheels.append(spec)
	return c


static func _vec3(value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 3:
		var a := value as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback
