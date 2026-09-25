class_name ChassisBuilder
extends RefCounted
## Внешний вид машины.
##
## Геометрия по-прежнему процедурная и по-прежнему берёт пропорции из того же
## конфига, что и физика: силуэт не может разойтись с габаритами и колёсной
## базой, потому что это одни и те же числа.
##
## Панели собраны из коробок со снятой фаской. Разница с обычным BoxMesh
## заметна сразу: острое математическое ребро свет не ловит и читается как
## наклейка, фаска даёт по блику на каждом ребре — и машина перестаёт быть
## набором кубиков, не превращаясь при этом в модель на сто тысяч полигонов.
##
## Окрашиваемые панели собираются отдельным списком: по нему потом ходит
## грязь, пыль и верблюжьи плевки — они должны ложиться на кузов, но не на
## стекло и не на резину.

const CAB_COLOUR := Color(0.84, 0.74, 0.50)
const BODY_COLOUR := Color(0.72, 0.61, 0.38)
const DARK_COLOUR := Color(0.18, 0.18, 0.20)
const METAL_COLOUR := Color(0.40, 0.39, 0.36)
const RUBBER_COLOUR := Color(0.11, 0.11, 0.12)
const LAMP_COLOUR := Color(0.94, 0.92, 0.80)
const TAIL_COLOUR := Color(0.55, 0.10, 0.08)


## Собирает машину целиком. Возвращает:
##   chassis    — кузов;
##   wheels     — колёса отдельными узлами, их двигает физика;
##   headlights — фары;
##   cabin      — узлы кабины: руль, рычаг, точка глаз, подсветка приёмника;
##   paint      — панели, на которые ложится грязь;
##   tail_lamps — задние фонари.
static func build(config: VehicleConfig) -> Dictionary:
	if config.body_style == &"van":
		return VanBuilder.build(config)
	var size := config.body_size
	var offset := config.body_offset
	var chassis := Node3D.new()
	chassis.name = "Chassis"
	var half_length := size.z * 0.5
	var paint: Array[MeshInstance3D] = []

	var add := func(node: Node3D, at: Vector3, painted: bool = false) -> Node3D:
		node.position = offset + at
		chassis.add_child(node)
		if painted and node is MeshInstance3D:
			paint.append(node as MeshInstance3D)
		return node

	# --- Рама -------------------------------------------------------------
	# Два лонжерона вместо одной балки: между ними видно мост и карданный вал,
	# и машина перестаёт выглядеть монолитом на колёсах.
	for side: int in 2:
		var frame_sign := 1.0 if side == 0 else -1.0
		add.call(
			MeshFactory.panel(
				Vector3(size.x * 0.10, size.y * 0.16, size.z * 0.94), DARK_COLOUR, 0.8, 0.35, 0.02
			),
			Vector3(frame_sign * size.x * 0.30, -size.y * 0.34, 0.0)
		)
	add.call(
		MeshFactory.tube(0.045, size.z * 0.50, METAL_COLOUR, Vector3.FORWARD, 0.45, 0.7, 8),
		Vector3(0.0, -size.y * 0.34, size.z * 0.08)
	)

	# --- Капот ------------------------------------------------------------
	var bonnet := MeshFactory.panel(
		Vector3(size.x * 0.92, size.y * 0.34, size.z * 0.24), CAB_COLOUR, 0.48, 0.12, 0.05
	)
	add.call(bonnet, Vector3(0.0, -size.y * 0.04, -half_length + size.z * 0.14), true)
	# Наклон капота вниз к решётке: нос перестаёт быть тупым срезом.
	bonnet.rotation = Vector3(deg_to_rad(2.5), 0.0, 0.0)

	add.call(
		MeshFactory.panel(
			Vector3(size.x * 0.62, size.y * 0.24, 0.06), Color(0.13, 0.13, 0.14), 0.7, 0.4, 0.015
		),
		Vector3(0.0, -size.y * 0.06, -half_length + 0.04)
	)
	for i: int in 4:
		add.call(
			MeshFactory.panel(Vector3(size.x * 0.58, 0.018, 0.02), METAL_COLOUR, 0.4, 0.7, 0.005),
			Vector3(0.0, -size.y * 0.13 + float(i) * size.y * 0.045, -half_length + 0.015)
		)

	# --- Кабина -----------------------------------------------------------
	var cab_z := -half_length + size.z * 0.34
	add.call(
		MeshFactory.panel(
			Vector3(size.x * 0.94, size.y * 0.98, size.z * 0.30), CAB_COLOUR, 0.48, 0.12, 0.05
		),
		Vector3(0.0, size.y * 0.34, cab_z), true
	)
	add.call(
		MeshFactory.panel(Vector3(size.x * 0.90, 0.06, size.z * 0.30), CAB_COLOUR, 0.55, 0.1, 0.03),
		Vector3(0.0, size.y * 0.84, cab_z), true
	)

	# Стекло отдельной функцией не из прихоти: у него прозрачность, низкая
	# шероховатость и выключенная тень. Стеклянная панель, бросающая плотную
	# тень, выдаёт подделку мгновенно.
	var windscreen := MeshFactory.glass(Vector3(size.x * 0.80, size.y * 0.48, 0.03))
	add.call(windscreen, Vector3(0.0, size.y * 0.52, cab_z - size.z * 0.145))
	windscreen.rotation = Vector3(deg_to_rad(-15.0), 0.0, 0.0)

	add.call(
		MeshFactory.glass(Vector3(size.x * 0.70, size.y * 0.30, 0.03)),
		Vector3(0.0, size.y * 0.56, cab_z + size.z * 0.148)
	)

	for side: int in 2:
		var door_sign := 1.0 if side == 0 else -1.0
		add.call(
			MeshFactory.glass(Vector3(0.03, size.y * 0.34, size.z * 0.22)),
			Vector3(door_sign * size.x * 0.472, size.y * 0.54, cab_z)
		)
		# Линия двери: тонкая тёмная щель, читается как дверь, а не как борт.
		add.call(
			MeshFactory.panel(Vector3(0.012, size.y * 0.92, 0.018), DARK_COLOUR, 0.9, 0.0, 0.003),
			Vector3(door_sign * size.x * 0.474, size.y * 0.32, cab_z + size.z * 0.14)
		)
		add.call(
			MeshFactory.panel(Vector3(0.03, 0.035, 0.13), METAL_COLOUR, 0.4, 0.6, 0.008),
			Vector3(door_sign * size.x * 0.482, size.y * 0.26, cab_z + size.z * 0.06)
		)
		add.call(
			MeshFactory.tube(0.014, 0.22, DARK_COLOUR, Vector3.RIGHT, 0.6, 0.4, 6),
			Vector3(door_sign * size.x * 0.52, size.y * 0.56, cab_z - size.z * 0.12)
		)
		add.call(
			MeshFactory.panel(Vector3(0.03, 0.22, 0.13), Color(0.32, 0.35, 0.37), 0.12, 0.8, 0.008),
			Vector3(door_sign * size.x * 0.62, size.y * 0.56, cab_z - size.z * 0.12)
		)

	# --- Крылья -----------------------------------------------------------
	for spec: VehicleConfig.WheelSpec in config.wheels:
		_build_arch(chassis, spec, paint)

	# --- Платформа --------------------------------------------------------
	var deck_z := half_length - size.z * 0.28
	add.call(
		MeshFactory.panel(
			Vector3(size.x * 0.98, size.y * 0.10, size.z * 0.52), BODY_COLOUR, 0.72, 0.05, 0.02
		),
		Vector3(0.0, -size.y * 0.08, deck_z), true
	)
	for side: int in 2:
		var wall_sign := 1.0 if side == 0 else -1.0
		add.call(
			MeshFactory.panel(
				Vector3(size.x * 0.05, size.y * 0.42, size.z * 0.52), BODY_COLOUR, 0.72, 0.05, 0.02
			),
			Vector3(wall_sign * size.x * 0.47, size.y * 0.16, deck_z), true
		)
		for rib: int in 4:
			var along := (float(rib) + 0.5) / 4.0 - 0.5
			add.call(
				MeshFactory.panel(
					Vector3(size.x * 0.02, size.y * 0.40, 0.05), BODY_COLOUR.darkened(0.12), 0.75, 0.05, 0.008
				),
				Vector3(wall_sign * size.x * 0.497, size.y * 0.16, deck_z + along * size.z * 0.48)
			)
	add.call(
		MeshFactory.panel(
			Vector3(size.x * 0.98, size.y * 0.42, 0.07), BODY_COLOUR, 0.72, 0.05, 0.02
		),
		Vector3(0.0, size.y * 0.16, half_length - 0.05), true
	)

	# --- Оснастка ---------------------------------------------------------
	add.call(
		MeshFactory.tube(
			size.y * 0.19, size.z * 0.28, Color(0.32, 0.31, 0.30), Vector3.FORWARD, 0.55, 0.55, 12
		),
		Vector3(-size.x * 0.42, -size.y * 0.30, deck_z - size.z * 0.10)
	)
	# Выхлоп поднят вдоль кабины: у пустынных машин он такой, чтобы не хлебать
	# песок на броде и в яме.
	add.call(
		MeshFactory.tube(0.055, size.y * 1.10, Color(0.30, 0.29, 0.28), Vector3.UP, 0.5, 0.65, 10),
		Vector3(size.x * 0.46, size.y * 0.42, cab_z + size.z * 0.17)
	)
	add.call(
		MeshFactory.tube(0.05, size.y * 0.95, Color(0.16, 0.16, 0.17), Vector3.UP, 0.8, 0.1, 10),
		Vector3(-size.x * 0.46, size.y * 0.40, cab_z - size.z * 0.10)
	)
	add.call(
		MeshFactory.tube(0.05, 0.22, Color(0.16, 0.16, 0.17), Vector3.FORWARD, 0.8, 0.1, 10),
		Vector3(-size.x * 0.46, size.y * 0.90, cab_z - size.z * 0.16)
	)

	var rack := Node3D.new()
	rack.name = "RoofRack"
	add.call(rack, Vector3(0.0, size.y * 0.90, cab_z))
	for side: int in 2:
		var rail_sign := 1.0 if side == 0 else -1.0
		var rail := MeshFactory.tube(0.018, size.z * 0.28, METAL_COLOUR, Vector3.FORWARD, 0.5, 0.6, 6)
		rail.position = Vector3(rail_sign * size.x * 0.40, 0.04, 0.0)
		rack.add_child(rail)
	for i: int in 2:
		var can := MeshFactory.panel(Vector3(0.17, 0.26, 0.09), Color(0.36, 0.40, 0.31), 0.8, 0.1, 0.015)
		can.position = Vector3(-size.x * 0.22 + float(i) * size.x * 0.20, 0.17, -size.z * 0.06)
		rack.add_child(can)

	var spare := MeshFactory.wheel(config.wheels[0].radius * 0.92, config.wheels[0].width * 0.9)
	spare.rotation = Vector3(0.0, 0.0, PI * 0.5)
	add.call(spare, Vector3(0.0, size.y * 0.12, half_length - 0.24))

	# Антенна здесь не для красоты: радио в кабине настоящее, и антенна —
	# единственное, что говорит об этом снаружи.
	var antenna := MeshFactory.tube(0.008, size.y * 1.3, Color(0.22, 0.22, 0.23), Vector3.UP, 0.5, 0.4, 5)
	add.call(antenna, Vector3(size.x * 0.40, size.y * 1.20, cab_z - size.z * 0.12))
	antenna.rotation = Vector3(deg_to_rad(6.0), 0.0, deg_to_rad(-8.0))

	add.call(
		MeshFactory.panel(Vector3(size.x * 1.02, size.y * 0.16, 0.14), DARK_COLOUR, 0.5, 0.55, 0.03),
		Vector3(0.0, -size.y * 0.20, -half_length - 0.06)
	)
	for i: int in 3:
		add.call(
			MeshFactory.tube(0.022, size.y * 0.46, DARK_COLOUR, Vector3.UP, 0.5, 0.55, 6),
			Vector3((float(i) - 1.0) * size.x * 0.26, size.y * 0.02, -half_length - 0.06)
		)

	add.call(
		MeshFactory.panel(Vector3(0.34, 0.11, 0.015), Color(0.88, 0.86, 0.80), 0.4, 0.0, 0.004),
		Vector3(0.0, -size.y * 0.20, half_length + 0.02)
	)

	# --- Свет -------------------------------------------------------------
	var headlights: Array[SpotLight3D] = []
	var tail_lamps: Array[MeshInstance3D] = []
	for side: int in 2:
		var lamp_sign := 1.0 if side == 0 else -1.0
		add.call(
			MeshFactory.panel(Vector3(0.26, 0.17, 0.07), LAMP_COLOUR, 0.18, 0.1, 0.02),
			Vector3(lamp_sign * size.x * 0.33, -size.y * 0.04, -half_length + 0.03)
		)

		var light := SpotLight3D.new()
		light.name = "Headlight%d" % side
		light.position = offset + Vector3(
			lamp_sign * size.x * 0.33, -size.y * 0.04, -half_length - 0.12
		)
		light.rotation = Vector3(deg_to_rad(-4.0), 0.0, 0.0)
		light.spot_range = 90.0
		light.spot_angle = 34.0
		light.spot_angle_attenuation = 0.6
		light.light_energy = 4.0
		light.light_color = Color(1.0, 0.96, 0.86)
		light.shadow_enabled = false
		light.visible = false
		chassis.add_child(light)
		headlights.append(light)

		add.call(
			MeshFactory.panel(Vector3(0.10, 0.09, 0.05), Color(0.85, 0.48, 0.10), 0.3, 0.0, 0.012),
			Vector3(lamp_sign * size.x * 0.45, -size.y * 0.04, -half_length + 0.03)
		)

		var tail: MeshInstance3D = MeshFactory.panel(
			Vector3(0.13, 0.20, 0.05), TAIL_COLOUR, 0.25, 0.0, 0.012
		)
		add.call(tail, Vector3(lamp_sign * size.x * 0.42, -size.y * 0.04, half_length + 0.01))
		tail_lamps.append(tail)

	# --- Кабина изнутри ---------------------------------------------------
	var volume := CabinBuilder.truck_volume(config)
	var cabin := CabinBuilder.build(config, volume[0], volume[1])
	chassis.add_child(cabin["root"])

	# --- Колёса -----------------------------------------------------------
	var wheels: Array[Node3D] = []
	for spec: VehicleConfig.WheelSpec in config.wheels:
		var wheel := MeshFactory.wheel(spec.radius, spec.width)
		wheel.name = "Wheel_%d_%d" % [roundi(spec.position.x * 10.0), roundi(spec.position.z * 10.0)]
		wheels.append(wheel)

	return {
		"chassis": chassis,
		"wheels": wheels,
		"headlights": headlights,
		"cabin": cabin,
		"paint": paint,
		"tail_lamps": tail_lamps,
	}


## Колёсная арка: дуга из коротких сегментов над колесом плюс брызговик.
## Именно арка отделяет силуэт внедорожника от силуэта ящика на колёсах.
static func _build_arch(chassis: Node3D, spec: VehicleConfig.WheelSpec,
		paint: Array[MeshInstance3D]) -> void:
	var radius := spec.radius * 1.20
	var width := spec.width * 1.28
	var segments := 7
	var arch := Node3D.new()
	arch.name = "Arch_%d_%d" % [roundi(spec.position.x * 10.0), roundi(spec.position.z * 10.0)]
	arch.position = Vector3(spec.position.x, spec.position.y + 0.02, spec.position.z)
	chassis.add_child(arch)
	for i: int in segments:
		var angle := PI * (float(i) + 0.5) / float(segments)
		var piece: MeshInstance3D = MeshFactory.panel(
			Vector3(width, 0.042, radius * PI / float(segments) * 1.22),
			BODY_COLOUR.darkened(0.05), 0.7, 0.05, 0.012
		)
		piece.position = Vector3(0.0, sin(angle) * radius, cos(angle) * radius)
		piece.rotation = Vector3(-angle + PI * 0.5, 0.0, 0.0)
		arch.add_child(piece)
		paint.append(piece)
	var flap := MeshFactory.panel(
		Vector3(width * 0.9, radius * 0.55, 0.012), RUBBER_COLOUR, 0.95, 0.0, 0.004
	)
	flap.position = Vector3(0.0, -radius * 0.22, radius * 0.92)
	arch.add_child(flap)
