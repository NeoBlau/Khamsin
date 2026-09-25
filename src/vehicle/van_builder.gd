class_name VanBuilder
extends RefCounted
## Облик маршрутки.
##
## Отдельно от бортового грузовика, потому что это другой силуэт, а не тот же
## с другими числами: у фургона нет платформы и рамы, зато есть сплошной борт
## во всю длину, полоса окон и сдвижная дверь. Попытка выразить это через
## параметры грузовика даёт пикап с высокой будкой — узнаётся как что угодно,
## кроме маршрутки.
##
## Система координат: всё считается от центра габаритной коробки кузова, а у
## фургона эта коробка начинается на уровне пола салона, то есть выше осей.
## Если задать её так, чтобы низ оказался ниже осей, колёса окажутся внутри
## кузова — снаружи их просто не будет видно, и понять почему по коду нельзя.
##
## Возвращает тот же словарь, что и ChassisBuilder: остальной код не должен
## знать, какой именно кузов ему собрали.

const BODY := Color(0.88, 0.87, 0.83)
const STRIPE := Color(0.22, 0.44, 0.62)
const DARK := Color(0.18, 0.18, 0.20)
const METAL := Color(0.44, 0.43, 0.40)
const LAMP := Color(0.94, 0.92, 0.80)
const TAIL := Color(0.58, 0.12, 0.09)


static func build(config: VehicleConfig) -> Dictionary:
	var size := config.body_size
	var offset := config.body_offset
	var chassis := Node3D.new()
	chassis.name = "Chassis"
	var half := size * 0.5
	var paint: Array[MeshInstance3D] = []

	var add := func(node: Node3D, at: Vector3, painted: bool = false) -> Node3D:
		node.position = offset + at
		chassis.add_child(node)
		if painted and node is MeshInstance3D:
			paint.append(node as MeshInstance3D)
		return node

	# --- Кузов ------------------------------------------------------------
	# Один короб почти во всю длину: он и есть фургон.
	add.call(
		MeshFactory.panel(
			Vector3(size.x * 0.96, size.y * 0.94, size.z * 0.84), BODY, 0.42, 0.14, 0.09
		),
		Vector3(0.0, 0.0, size.z * 0.03), true
	)
	# Скошенный нос ниже основного объёма — по нему фургон и отличается от
	# коробки на колёсах.
	add.call(
		MeshFactory.panel(
			Vector3(size.x * 0.90, size.y * 0.32, size.z * 0.13), BODY, 0.42, 0.14, 0.07
		),
		Vector3(0.0, -size.y * 0.36, -half.z + size.z * 0.05), true
	)
	# Крыша с вентиляционным люком.
	add.call(
		MeshFactory.panel(
			Vector3(size.x * 0.92, 0.06, size.z * 0.82), BODY.darkened(0.05), 0.55, 0.1, 0.03
		),
		Vector3(0.0, size.y * 0.47, size.z * 0.03), true
	)
	add.call(
		MeshFactory.panel(
			Vector3(size.x * 0.24, 0.08, size.x * 0.24), Color(0.80, 0.80, 0.78), 0.6, 0.1, 0.015
		),
		Vector3(0.0, size.y * 0.52, -size.z * 0.06)
	)

	# --- Остекление -------------------------------------------------------
	var windscreen := MeshFactory.glass(Vector3(size.x * 0.84, size.y * 0.66, 0.03))
	add.call(windscreen, Vector3(0.0, size.y * 0.04, -half.z + size.z * 0.095))
	windscreen.rotation = Vector3(deg_to_rad(-20.0), 0.0, 0.0)

	add.call(
		MeshFactory.glass(Vector3(size.x * 0.78, size.y * 0.34, 0.03)),
		Vector3(0.0, size.y * 0.12, half.z - size.z * 0.06)
	)

	for side: int in 2:
		var s := 1.0 if side == 0 else -1.0
		# Сплошная полоса окон по борту.
		add.call(
			MeshFactory.glass(Vector3(0.03, size.y * 0.36, size.z * 0.58)),
			Vector3(s * size.x * 0.487, size.y * 0.14, size.z * 0.06)
		)
		# Стойка между окнами: без неё полоса стекла читается как щель.
		add.call(
			MeshFactory.panel(
				Vector3(0.05, size.y * 0.38, 0.08), BODY.darkened(0.08), 0.5, 0.1, 0.01
			),
			Vector3(s * size.x * 0.487, size.y * 0.14, -size.z * 0.08)
		)
		# Синяя полоса под окнами.
		add.call(
			MeshFactory.panel(
				Vector3(0.03, size.y * 0.09, size.z * 0.80), STRIPE, 0.45, 0.2, 0.01
			),
			Vector3(s * size.x * 0.487, -size.y * 0.18, size.z * 0.03)
		)
		# Зеркало на короткой ножке.
		add.call(
			MeshFactory.tube(0.012, 0.16, DARK, Vector3.RIGHT, 0.6, 0.4, 6),
			Vector3(s * size.x * 0.53, size.y * 0.20, -half.z + size.z * 0.17)
		)
		add.call(
			MeshFactory.panel(
				Vector3(0.025, 0.18, 0.11), Color(0.32, 0.35, 0.37), 0.12, 0.8, 0.006
			),
			Vector3(s * size.x * 0.61, size.y * 0.20, -half.z + size.z * 0.17)
		)

	# Сдвижная дверь — только справа, как и положено.
	for z: float in [-size.z * 0.04, size.z * 0.24]:
		add.call(
			MeshFactory.panel(Vector3(0.02, size.y * 0.88, 0.03), DARK, 0.9, 0.0, 0.004),
			Vector3(size.x * 0.49, 0.0, z)
		)
	add.call(
		MeshFactory.panel(Vector3(0.04, 0.05, 0.16), METAL, 0.4, 0.6, 0.01),
		Vector3(size.x * 0.50, -size.y * 0.06, size.z * 0.18)
	)

	# --- Перед и зад ------------------------------------------------------
	add.call(
		MeshFactory.panel(
			Vector3(size.x * 0.98, size.y * 0.16, 0.13), Color(0.30, 0.30, 0.32), 0.6, 0.2, 0.03
		),
		Vector3(0.0, -size.y * 0.50, -half.z - 0.03)
	)
	add.call(
		MeshFactory.panel(
			Vector3(size.x * 0.50, size.y * 0.12, 0.05), Color(0.14, 0.14, 0.15), 0.7, 0.3, 0.012
		),
		Vector3(0.0, -size.y * 0.36, -half.z + 0.02)
	)
	add.call(
		MeshFactory.panel(
			Vector3(size.x * 0.98, size.y * 0.14, 0.11), Color(0.30, 0.30, 0.32), 0.6, 0.2, 0.03
		),
		Vector3(0.0, -size.y * 0.50, half.z + 0.02)
	)
	add.call(
		MeshFactory.panel(Vector3(0.32, 0.10, 0.015), Color(0.88, 0.86, 0.80), 0.4, 0.0, 0.004),
		Vector3(0.0, -size.y * 0.42, half.z + 0.05)
	)
	add.call(
		MeshFactory.tube(0.04, size.z * 0.26, Color(0.32, 0.31, 0.30), Vector3.FORWARD, 0.55, 0.5, 8),
		Vector3(-size.x * 0.30, -size.y * 0.56, half.z - size.z * 0.16)
	)

	var headlights: Array[SpotLight3D] = []
	var tail_lamps: Array[MeshInstance3D] = []
	for side: int in 2:
		var s := 1.0 if side == 0 else -1.0
		add.call(
			MeshFactory.panel(Vector3(0.24, 0.14, 0.06), LAMP, 0.18, 0.1, 0.018),
			Vector3(s * size.x * 0.34, -size.y * 0.36, -half.z + 0.02)
		)
		var light := SpotLight3D.new()
		light.name = "Headlight%d" % side
		light.position = offset + Vector3(
			s * size.x * 0.34, -size.y * 0.36, -half.z - 0.12
		)
		light.rotation = Vector3(deg_to_rad(-3.0), 0.0, 0.0)
		light.spot_range = 70.0
		light.spot_angle = 32.0
		light.spot_angle_attenuation = 0.6
		light.light_energy = 3.4
		light.light_color = Color(1.0, 0.95, 0.84)
		light.shadow_enabled = false
		light.visible = false
		chassis.add_child(light)
		headlights.append(light)

		var tail: MeshInstance3D = MeshFactory.panel(
			Vector3(0.11, 0.26, 0.05), TAIL, 0.25, 0.0, 0.012
		)
		add.call(tail, Vector3(s * size.x * 0.42, -size.y * 0.24, half.z + 0.01))
		tail_lamps.append(tail)

	# --- Салон ------------------------------------------------------------
	var volume := CabinBuilder.van_volume(config)
	var cabin := CabinBuilder.build(config, volume[0], volume[1])
	chassis.add_child(cabin["root"])
	_build_seat_rows(chassis, config)

	var wheels: Array[Node3D] = []
	for spec: VehicleConfig.WheelSpec in config.wheels:
		var wheel := MeshFactory.wheel(spec.radius, spec.width)
		wheel.name = "Wheel_%d_%d" % [roundi(spec.position.x * 10.0), roundi(spec.position.z * 10.0)]
		wheels.append(wheel)
		# Арка вокруг колеса: у фургона она едва заметная, но без неё колесо
		# выглядит приставленным к ровной стенке. Красится вместе с кузовом —
		# грязь на арках заметнее всего.
		_build_arch(chassis, spec, paint)

	return {
		"chassis": chassis,
		"wheels": wheels,
		"headlights": headlights,
		"cabin": cabin,
		"paint": paint,
		"tail_lamps": tail_lamps,
	}


static func _build_arch(chassis: Node3D, spec: VehicleConfig.WheelSpec,
		paint: Array[MeshInstance3D]) -> void:
	var radius := spec.radius * 1.18
	var arch := Node3D.new()
	arch.name = "Arch_%d_%d" % [roundi(spec.position.x * 10.0), roundi(spec.position.z * 10.0)]
	arch.position = Vector3(spec.position.x, spec.position.y, spec.position.z)
	chassis.add_child(arch)
	var segments := 5
	for i: int in segments:
		var angle := PI * (float(i) + 0.5) / float(segments)
		var piece := MeshFactory.panel(
			Vector3(spec.width * 1.35, 0.035, radius * PI / float(segments) * 1.2),
			Color(0.32, 0.32, 0.33), 0.9, 0.0, 0.008
		)
		piece.position = Vector3(0.0, sin(angle) * radius, cos(angle) * radius)
		piece.rotation = Vector3(-angle + PI * 0.5, 0.0, 0.0)
		arch.add_child(piece)
		paint.append(piece)


## Ряды пассажирских сидений. Их видно сквозь окна, и именно по ним машина
## читается как пассажирская, а не как фургон с грузом.
static func _build_seat_rows(chassis: Node3D, config: VehicleConfig) -> void:
	var size := config.body_size
	var offset := config.body_offset
	var colour := Color(0.30, 0.26, 0.24)
	for row: int in 3:
		var z := size.z * (0.04 + float(row) * 0.17)
		for side: int in 2:
			var s := 1.0 if side == 0 else -1.0
			var base := MeshFactory.panel(
				Vector3(size.x * 0.32, 0.10, size.z * 0.10), colour, 0.95, 0.0, 0.02
			)
			base.position = offset + Vector3(s * size.x * 0.26, -size.y * 0.34, z)
			chassis.add_child(base)
			var back := MeshFactory.panel(
				Vector3(size.x * 0.32, size.y * 0.34, 0.08), colour, 0.95, 0.0, 0.02
			)
			back.position = offset + Vector3(
				s * size.x * 0.26, -size.y * 0.12, z + size.z * 0.055
			)
			chassis.add_child(back)
