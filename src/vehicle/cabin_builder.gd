class_name CabinBuilder
extends RefCounted
## Кабина изнутри. Нужна ровно для вида от первого лица: снаружи её не видно,
## а изнутри без неё игрок висит в пустоте с приборами на экране.
##
## Две детали здесь не украшение. Руль поворачивается вслед за настоящим углом
## колёс, рычаг ходит по передачам — и то и другое берётся из физики, а не
## анимируется отдельно. В виде от первого лица это единственный способ
## почувствовать, что машина отвечает: приборы на экране читаются глазами,
## а руль виден боковым зрением.

const DASH_COLOUR := Color(0.13, 0.12, 0.12)
const TRIM_COLOUR := Color(0.21, 0.19, 0.17)
const SEAT_COLOUR := Color(0.28, 0.24, 0.20)
const METAL_COLOUR := Color(0.42, 0.41, 0.38)


## Собирает кабину. Возвращает {root, wheel, lever, eye, radio_light}.
##   root        — узел, который вешается на кузов;
##   wheel       — руль, крутится вокруг своей оси;
##   lever       — рычаг передач;
##   eye         — точка глаз водителя;
##   radio_light — подсветка приёмника, гаснет с выключенным радио.
static func build(config: VehicleConfig) -> Dictionary:
	var size := config.body_size
	var offset := config.body_offset
	var half_length := size.z * 0.5
	# Кабина стоит над передней осью. Водитель слева: движение здесь
	# правостороннее, и руль у машины левый.
	var cabin_z := -half_length + size.z * 0.34
	var driver_x := -size.x * 0.22

	var root := Node3D.new()
	root.name = "Cabin"

	# Пол и моторный тоннель между сиденьями.
	var floor_panel := MeshFactory.panel(
		Vector3(size.x * 0.88, 0.05, size.z * 0.30), TRIM_COLOUR, 0.9, 0.0, 0.02
	)
	floor_panel.position = offset + Vector3(0.0, -size.y * 0.06, cabin_z)
	root.add_child(floor_panel)

	var tunnel := MeshFactory.panel(
		Vector3(size.x * 0.20, size.y * 0.22, size.z * 0.28), TRIM_COLOUR, 0.85, 0.0, 0.04
	)
	tunnel.position = offset + Vector3(0.0, size.y * 0.02, cabin_z)
	root.add_child(tunnel)

	# Обшивка потолка. Без неё изнутри видно крышу, покрашенную в цвет кузова,
	# и кабина выглядит вывернутой наизнанку.
	var headliner := MeshFactory.panel(
		Vector3(size.x * 0.86, 0.03, size.z * 0.28), Color(0.30, 0.28, 0.25), 0.95, 0.0, 0.01
	)
	headliner.position = offset + Vector3(0.0, size.y * 0.79, cabin_z)
	root.add_child(headliner)

	# Торпедо: наклонная панель под лобовым стеклом.
	var dash := MeshFactory.panel(
		Vector3(size.x * 0.86, size.y * 0.24, 0.22), DASH_COLOUR, 0.82, 0.0, 0.03
	)
	dash.position = offset + Vector3(0.0, size.y * 0.16, cabin_z - size.z * 0.14)
	dash.rotation = Vector3(deg_to_rad(-14.0), 0.0, 0.0)
	root.add_child(dash)

	# Козырёк приборов над рулём — он и прячет блик на стекле приборов.
	var binnacle := MeshFactory.panel(
		Vector3(size.x * 0.30, 0.16, 0.20), DASH_COLOUR, 0.7, 0.0, 0.04
	)
	binnacle.position = offset + Vector3(driver_x, size.y * 0.30, cabin_z - size.z * 0.13)
	binnacle.rotation = Vector3(deg_to_rad(-22.0), 0.0, 0.0)
	root.add_child(binnacle)

	# Приёмник по центру торпедо, со своей подсветкой.
	var radio_face := MeshFactory.panel(
		Vector3(0.20, 0.09, 0.04), Color(0.09, 0.09, 0.10), 0.5, 0.2, 0.01
	)
	radio_face.position = offset + Vector3(0.0, size.y * 0.21, cabin_z - size.z * 0.135)
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

	# Рулевая колонка и руль. Ось руля наклонена — вертикальный руль в грузовике
	# выглядит как в автобусе, а лежащий плашмя как в легковой.
	var column := MeshFactory.tube(0.035, size.z * 0.16, METAL_COLOUR, Vector3.UP, 0.5, 0.6, 8)
	column.position = offset + Vector3(driver_x, size.y * 0.22, cabin_z - size.z * 0.085)
	column.rotation = Vector3(deg_to_rad(58.0), 0.0, 0.0)
	root.add_child(column)

	var wheel := Node3D.new()
	wheel.name = "SteeringWheel"
	wheel.position = offset + Vector3(driver_x, size.y * 0.34, cabin_z - size.z * 0.05)
	wheel.rotation = Vector3(deg_to_rad(-26.0), 0.0, 0.0)
	root.add_child(wheel)
	_build_wheel_rim(wheel, 0.22)

	# Рычаг передач: торчит из тоннеля, ходит вперёд-назад и вбок.
	var lever := Node3D.new()
	lever.name = "GearLever"
	lever.position = offset + Vector3(-size.x * 0.06, size.y * 0.13, cabin_z + size.z * 0.01)
	root.add_child(lever)
	var stick := MeshFactory.tube(0.018, 0.30, Color(0.18, 0.17, 0.16), Vector3.UP, 0.6, 0.3, 8)
	stick.position = Vector3(0.0, 0.15, 0.0)
	lever.add_child(stick)
	var knob := MeshFactory.panel(Vector3(0.07, 0.06, 0.07), Color(0.26, 0.17, 0.10), 0.55, 0.0, 0.025)
	knob.position = Vector3(0.0, 0.31, 0.0)
	lever.add_child(knob)

	# Сиденья. Водительское и пассажирское, с видимыми подголовниками.
	for side: int in 2:
		var sign_x := 1.0 if side == 0 else -1.0
		var seat_x := driver_x * sign_x
		var base := MeshFactory.panel(
			Vector3(size.x * 0.30, 0.10, size.z * 0.11), SEAT_COLOUR, 0.95, 0.0, 0.03
		)
		base.position = offset + Vector3(seat_x, size.y * 0.02, cabin_z + size.z * 0.06)
		root.add_child(base)
		var back := MeshFactory.panel(
			Vector3(size.x * 0.30, size.y * 0.34, 0.10), SEAT_COLOUR, 0.95, 0.0, 0.03
		)
		back.position = offset + Vector3(seat_x, size.y * 0.20, cabin_z + size.z * 0.11)
		back.rotation = Vector3(deg_to_rad(8.0), 0.0, 0.0)
		root.add_child(back)
		var headrest := MeshFactory.panel(
			Vector3(size.x * 0.18, 0.12, 0.09), SEAT_COLOUR, 0.95, 0.0, 0.03
		)
		headrest.position = offset + Vector3(seat_x, size.y * 0.42, cabin_z + size.z * 0.115)
		root.add_child(headrest)

	# Обшивка дверей изнутри — то, что видно боковым зрением.
	for side: int in 2:
		var sign_x := 1.0 if side == 0 else -1.0
		var card := MeshFactory.panel(
			Vector3(0.05, size.y * 0.34, size.z * 0.24), TRIM_COLOUR, 0.88, 0.0, 0.02
		)
		card.position = offset + Vector3(sign_x * size.x * 0.44, size.y * 0.16, cabin_z)
		root.add_child(card)
		var pull := MeshFactory.tube(0.02, size.z * 0.10, Color(0.16, 0.15, 0.14), Vector3.FORWARD, 0.7, 0.2, 6)
		pull.position = offset + Vector3(sign_x * size.x * 0.40, size.y * 0.22, cabin_z)
		root.add_child(pull)

	# Зеркало заднего вида на потолке.
	var mirror := MeshFactory.panel(Vector3(0.26, 0.07, 0.03), Color(0.30, 0.33, 0.35), 0.15, 0.7, 0.01)
	mirror.position = offset + Vector3(0.0, size.y * 0.58, cabin_z - size.z * 0.14)
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

	# Точка глаз водителя. Не центр кабины: человек сидит слева и смотрит
	# поверх торпедо, а не сквозь него.
	var eye := Node3D.new()
	eye.name = "DriverEye"
	eye.position = offset + Vector3(driver_x, size.y * 0.60, cabin_z + size.z * 0.055)
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
