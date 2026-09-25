class_name CabinBuilder
extends RefCounted
## Кабина изнутри. Нужна ровно для вида от первого лица: снаружи её не видно,
## а изнутри без неё игрок висит в пустоте с приборами на экране.
##
## Объём кабины передаётся явно, а не выводится из габаритов машины. Это не
## лишний параметр: у бортового грузовика кабина — небольшая часть длинного
## кузова, а у фургона кузов и есть салон. Кабина, посчитанная от габаритов,
## в фургоне оказывается выше крыши, и снаружи это выглядит как тёмный лист,
## висящий над машиной; найти причину по коду почти невозможно.
##
## Две детали здесь не украшение. Руль поворачивается вслед за настоящим углом
## колёс, рычаг ходит по передачам — и то и другое берётся из физики, а не
## анимируется отдельно. В виде от первого лица это единственный способ
## почувствовать, что машина отвечает: приборы читаются глазами, а руль —
## боковым зрением.

const DASH_COLOUR := Color(0.13, 0.12, 0.12)
const TRIM_COLOUR := Color(0.21, 0.19, 0.17)
const SEAT_COLOUR := Color(0.28, 0.24, 0.20)
const METAL_COLOUR := Color(0.42, 0.41, 0.38)
const HEADLINER := Color(0.30, 0.28, 0.25)


## Кабина бортового грузовика: над передней осью, высотой чуть меньше кузова.
static func truck_volume(config: VehicleConfig) -> Array:
	var size := config.body_size
	return [
		config.body_offset + Vector3(0.0, size.y * 0.30, -size.z * 0.5 + size.z * 0.34),
		Vector3(size.x * 0.88, size.y * 0.92, size.z * 0.30),
	]


## Кабина фургона: передняя треть салона, во всю его высоту.
static func van_volume(config: VehicleConfig) -> Array:
	var size := config.body_size
	return [
		config.body_offset + Vector3(0.0, -size.y * 0.04, -size.z * 0.5 + size.z * 0.21),
		Vector3(size.x * 0.90, size.y * 0.88, size.z * 0.34),
	]


## Собирает кабину. Возвращает {root, wheel, lever, eye, radio_light}.
static func build(config: VehicleConfig, centre: Vector3 = Vector3.INF,
		box: Vector3 = Vector3.ZERO) -> Dictionary:
	if box == Vector3.ZERO or centre == Vector3.INF:
		var fallback := truck_volume(config)
		centre = fallback[0]
		box = fallback[1]
	var half := box * 0.5
	# Водитель слева: движение здесь правостороннее, и руль у машины левый.
	var driver_x := -box.x * 0.26

	var root := Node3D.new()
	root.name = "Cabin"

	var at := func(x: float, y: float, z: float) -> Vector3:
		return centre + Vector3(x, y, z)

	# Пол и моторный тоннель между сиденьями.
	var floor_panel := MeshFactory.panel(
		Vector3(box.x * 0.94, 0.05, box.z * 0.92), TRIM_COLOUR, 0.9, 0.0, 0.02
	)
	floor_panel.position = at.call(0.0, -half.y + 0.03, 0.0)
	root.add_child(floor_panel)

	var tunnel := MeshFactory.panel(
		Vector3(box.x * 0.20, box.y * 0.20, box.z * 0.78), TRIM_COLOUR, 0.85, 0.0, 0.04
	)
	tunnel.position = at.call(0.0, -half.y * 0.60, 0.0)
	root.add_child(tunnel)

	# Обшивка потолка. Без неё изнутри видно крышу, покрашенную снаружи в цвет
	# кузова, и кабина выглядит вывернутой наизнанку.
	var headliner := MeshFactory.panel(
		Vector3(box.x * 0.90, 0.03, box.z * 0.88), HEADLINER, 0.95, 0.0, 0.01
	)
	headliner.position = at.call(0.0, half.y - 0.04, 0.0)
	root.add_child(headliner)

	# Торпедо: наклонная панель под лобовым стеклом.
	var dash := MeshFactory.panel(
		Vector3(box.x * 0.92, box.y * 0.26, 0.22), DASH_COLOUR, 0.82, 0.0, 0.03
	)
	dash.position = at.call(0.0, -half.y * 0.34, -half.z * 0.76)
	dash.rotation = Vector3(deg_to_rad(-14.0), 0.0, 0.0)
	root.add_child(dash)

	# Козырёк приборов над рулём — он и прячет блик на стекле приборов.
	var binnacle := MeshFactory.panel(
		Vector3(box.x * 0.34, 0.16, 0.20), DASH_COLOUR, 0.7, 0.0, 0.04
	)
	binnacle.position = at.call(driver_x, -half.y * 0.02, -half.z * 0.70)
	binnacle.rotation = Vector3(deg_to_rad(-22.0), 0.0, 0.0)
	root.add_child(binnacle)

	# Приёмник по центру торпедо, со своей подсветкой.
	var radio_face := MeshFactory.panel(
		Vector3(0.20, 0.09, 0.04), Color(0.09, 0.09, 0.10), 0.5, 0.2, 0.01
	)
	radio_face.position = at.call(0.0, -half.y * 0.22, -half.z * 0.72)
	root.add_child(radio_face)

	var radio_light := OmniLight3D.new()
	radio_light.name = "RadioGlow"
	radio_light.position = radio_face.position + Vector3(0.0, 0.0, 0.06)
	radio_light.light_color = Color(1.0, 0.62, 0.22)
	radio_light.light_energy = 0.35
	radio_light.omni_range = 0.7
	radio_light.shadow_enabled = false
	radio_light.visible = false
	root.add_child(radio_light)

	# Рулевая колонка и руль. Ось наклонена: вертикальный руль выглядит как в
	# автобусе, лежащий плашмя — как в легковой.
	var column := MeshFactory.tube(0.035, box.z * 0.34, METAL_COLOUR, Vector3.UP, 0.5, 0.6, 8)
	column.position = at.call(driver_x, -half.y * 0.42, -half.z * 0.52)
	column.rotation = Vector3(deg_to_rad(58.0), 0.0, 0.0)
	root.add_child(column)

	var wheel := Node3D.new()
	wheel.name = "SteeringWheel"
	wheel.position = at.call(driver_x, -half.y * 0.12, -half.z * 0.34)
	wheel.rotation = Vector3(deg_to_rad(-26.0), 0.0, 0.0)
	root.add_child(wheel)
	_build_wheel_rim(wheel, minf(0.205, box.x * 0.115))

	# Рычаг передач: торчит из тоннеля, ходит вперёд-назад и вбок.
	var lever := Node3D.new()
	lever.name = "GearLever"
	lever.position = at.call(-box.x * 0.07, -half.y * 0.52, -half.z * 0.05)
	root.add_child(lever)
	var stick := MeshFactory.tube(0.018, 0.30, Color(0.18, 0.17, 0.16), Vector3.UP, 0.6, 0.3, 8)
	stick.position = Vector3(0.0, 0.15, 0.0)
	lever.add_child(stick)
	var knob := MeshFactory.panel(Vector3(0.07, 0.06, 0.07), Color(0.26, 0.17, 0.10), 0.55, 0.0, 0.025)
	knob.position = Vector3(0.0, 0.31, 0.0)
	lever.add_child(knob)

	# Сиденья: водительское и пассажирское, с видимыми подголовниками.
	for side: int in 2:
		var seat_x := driver_x * (1.0 if side == 0 else -1.0)
		var base := MeshFactory.panel(
			Vector3(box.x * 0.30, 0.10, box.z * 0.28), SEAT_COLOUR, 0.95, 0.0, 0.03
		)
		base.position = at.call(seat_x, -half.y * 0.60, half.z * 0.46)
		root.add_child(base)
		var back := MeshFactory.panel(
			Vector3(box.x * 0.30, box.y * 0.38, 0.10), SEAT_COLOUR, 0.95, 0.0, 0.03
		)
		back.position = at.call(seat_x, -half.y * 0.08, half.z * 0.70)
		back.rotation = Vector3(deg_to_rad(8.0), 0.0, 0.0)
		root.add_child(back)
		var headrest := MeshFactory.panel(
			Vector3(box.x * 0.20, 0.12, 0.09), SEAT_COLOUR, 0.95, 0.0, 0.03
		)
		headrest.position = at.call(seat_x, half.y * 0.40, half.z * 0.74)
		root.add_child(headrest)

	# Обшивка дверей изнутри — то, что видно боковым зрением.
	for side: int in 2:
		var door_x := half.x * 0.94 * (1.0 if side == 0 else -1.0)
		var card := MeshFactory.panel(
			Vector3(0.05, box.y * 0.36, box.z * 0.60), TRIM_COLOUR, 0.88, 0.0, 0.02
		)
		card.position = at.call(door_x, -half.y * 0.26, 0.0)
		root.add_child(card)
		var pull := MeshFactory.tube(
			0.02, box.z * 0.22, Color(0.16, 0.15, 0.14), Vector3.FORWARD, 0.7, 0.2, 6
		)
		pull.position = at.call(door_x * 0.92, -half.y * 0.12, 0.0)
		root.add_child(pull)

	# Зеркало заднего вида на потолке.
	var mirror := MeshFactory.panel(Vector3(0.26, 0.07, 0.03), Color(0.30, 0.33, 0.35), 0.15, 0.7, 0.01)
	mirror.position = at.call(0.0, half.y * 0.70, -half.z * 0.70)
	root.add_child(mirror)

	# Чётки на зеркале. Мелочь, но кабина без неё стерильная.
	var beads := Node3D.new()
	beads.name = "Beads"
	beads.position = mirror.position + Vector3(0.0, -0.03, 0.02)
	root.add_child(beads)
	for i: int in 7:
		var bead := MeshFactory.panel(
			Vector3(0.018, 0.018, 0.018), Color(0.42, 0.28, 0.12), 0.4, 0.1, 0.006
		)
		var angle := float(i) / 6.0 * PI
		bead.position = Vector3(sin(angle) * 0.05, -0.02 - cos(angle) * 0.05 - 0.05, 0.0)
		beads.add_child(bead)

	# Точка глаз водителя: выше руля и заметно позади него. Отсюда виден верх
	# обода — ровно то, что водитель и видит.
	var eye := Node3D.new()
	eye.name = "DriverEye"
	eye.position = at.call(driver_x, half.y * 0.46, half.z * 0.42)
	root.add_child(eye)

	return {
		"root": root,
		"wheel": wheel,
		"lever": lever,
		"eye": eye,
		"radio_light": radio_light,
	}


## Обод руля из сегментов плюс три спицы. Тор в Godot есть, но он даёт гладкое
## кольцо, а грузовой руль — это обод с заметными спицами и ступицей.
static func _build_wheel_rim(parent: Node3D, radius: float) -> void:
	var segments := 24
	for i: int in segments:
		var angle := float(i) / float(segments) * TAU
		var segment := MeshFactory.panel(
			Vector3(0.022, 0.022, radius * TAU / float(segments) * 1.18),
			Color(0.14, 0.13, 0.13), 0.75, 0.0, 0.008
		)
		segment.position = Vector3(cos(angle) * radius, sin(angle) * radius, 0.0)
		segment.rotation = Vector3(0.0, 0.0, angle)
		parent.add_child(segment)
	for i: int in 3:
		var angle := float(i) / 3.0 * TAU + PI * 0.5
		var spoke := MeshFactory.panel(
			Vector3(0.022, radius * 0.9, 0.018), Color(0.20, 0.19, 0.18), 0.6, 0.3, 0.006
		)
		spoke.position = Vector3(cos(angle) * radius * 0.45, sin(angle) * radius * 0.45, -0.01)
		spoke.rotation = Vector3(0.0, 0.0, angle - PI * 0.5)
		parent.add_child(spoke)
	var hub := MeshFactory.panel(
		Vector3(0.075, 0.075, 0.035), Color(0.17, 0.16, 0.15), 0.55, 0.2, 0.012
	)
	hub.position = Vector3(0.0, 0.0, -0.015)
	parent.add_child(hub)
