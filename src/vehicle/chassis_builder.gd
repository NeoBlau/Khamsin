class_name ChassisBuilder
extends RefCounted
## Внешний вид машины из примитивов.
##
## Настоящих моделей в проекте пока нет, и это честнее заглушки в виде куба:
## пропорции берутся из того же конфига, что и физика, поэтому силуэт всегда
## соответствует габаритам и колёсной базе. Когда появится модель художника,
## меняется только эта функция.

const CAB_COLOUR := Color(0.86, 0.76, 0.52)
const BODY_COLOUR := Color(0.74, 0.63, 0.40)
const DARK_COLOUR := Color(0.20, 0.20, 0.22)
const GLASS_COLOUR := Color(0.16, 0.22, 0.26)


## Собирает кузов и колёса. Возвращает {chassis: Node3D, wheels: Array[Node3D],
## headlights: Array[SpotLight3D]}.
static func build(config: VehicleConfig) -> Dictionary:
	var size := config.body_size
	var offset := config.body_offset
	var chassis := Node3D.new()
	chassis.name = "Chassis"

	var half_length := size.z * 0.5

	# Рама: низкая балка во всю длину. На неё визуально опирается всё остальное.
	var frame := MeshFactory.box(Vector3(size.x * 0.86, size.y * 0.30, size.z * 0.94), DARK_COLOUR, 0.8, 0.3)
	frame.position = offset + Vector3(0.0, -size.y * 0.30, 0.0)
	chassis.add_child(frame)

	# Капот и кабина: кабина выше и сдвинута назад относительно носа.
	var bonnet := MeshFactory.box(Vector3(size.x * 0.92, size.y * 0.42, size.z * 0.22), CAB_COLOUR, 0.55)
	bonnet.position = offset + Vector3(0.0, -size.y * 0.10, -half_length + size.z * 0.13)
	chassis.add_child(bonnet)

	var cab := MeshFactory.box(Vector3(size.x * 0.94, size.y * 0.78, size.z * 0.26), CAB_COLOUR, 0.55)
	cab.position = offset + Vector3(0.0, size.y * 0.16, -half_length + size.z * 0.37)
	chassis.add_child(cab)

	var windscreen := MeshFactory.box(Vector3(size.x * 0.80, size.y * 0.34, 0.06), GLASS_COLOUR, 0.15, 0.2)
	windscreen.position = offset + Vector3(0.0, size.y * 0.30, -half_length + size.z * 0.245)
	windscreen.rotation = Vector3(deg_to_rad(-12.0), 0.0, 0.0)
	chassis.add_child(windscreen)

	# Грузовая платформа с бортами: именно её объём ограничивает загрузку.
	var deck := MeshFactory.box(Vector3(size.x, size.y * 0.12, size.z * 0.52), BODY_COLOUR, 0.75)
	deck.position = offset + Vector3(0.0, -size.y * 0.06, half_length - size.z * 0.29)
	chassis.add_child(deck)
	for side: int in 2:
		var wall := MeshFactory.box(
			Vector3(size.x * 0.06, size.y * 0.40, size.z * 0.52), BODY_COLOUR, 0.75
		)
		wall.position = offset + Vector3(
			(size.x * 0.47) * (1.0 if side == 0 else -1.0),
			size.y * 0.14,
			half_length - size.z * 0.29
		)
		chassis.add_child(wall)
	var tailgate := MeshFactory.box(Vector3(size.x, size.y * 0.40, 0.08), BODY_COLOUR, 0.75)
	tailgate.position = offset + Vector3(0.0, size.y * 0.14, half_length - 0.06)
	chassis.add_child(tailgate)

	# Бак и запаска — то, из-за чего силуэт читается как рабочая машина.
	var tank := CylinderMesh.new()
	tank.top_radius = size.y * 0.20
	tank.bottom_radius = size.y * 0.20
	tank.height = size.z * 0.30
	tank.radial_segments = 12
	var tank_instance := MeshInstance3D.new()
	tank_instance.mesh = tank
	tank_instance.material_override = MeshFactory.standard_material(Color(0.34, 0.33, 0.31), 0.6, 0.5)
	tank_instance.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	tank_instance.position = offset + Vector3(-size.x * 0.42, -size.y * 0.34, half_length - size.z * 0.42)
	chassis.add_child(tank_instance)

	var spare := MeshFactory.wheel(config.wheels[0].radius * 0.92, config.wheels[0].width * 0.9)
	spare.rotation = Vector3(0.0, 0.0, PI * 0.5)
	spare.position = offset + Vector3(0.0, size.y * 0.10, half_length - 0.22)
	chassis.add_child(spare)

	var bar := MeshFactory.box(Vector3(size.x * 1.02, size.y * 0.16, 0.12), DARK_COLOUR, 0.5, 0.6)
	bar.position = offset + Vector3(0.0, -size.y * 0.18, -half_length - 0.05)
	chassis.add_child(bar)

	var headlights: Array[SpotLight3D] = []
	for side: int in 2:
		var sign_x := 1.0 if side == 0 else -1.0
		var lamp := MeshFactory.box(Vector3(0.24, 0.18, 0.06), Color(0.92, 0.90, 0.78), 0.2)
		lamp.position = offset + Vector3(sign_x * size.x * 0.33, -size.y * 0.06, -half_length + 0.02)
		chassis.add_child(lamp)

		var light := SpotLight3D.new()
		light.name = "Headlight%d" % side
		light.position = lamp.position + Vector3(0.0, 0.0, -0.15)
		light.rotation = Vector3(deg_to_rad(-4.0), 0.0, 0.0)
		light.spot_range = 85.0
		light.spot_angle = 34.0
		light.spot_angle_attenuation = 0.6
		light.light_energy = 4.0
		light.light_color = Color(1.0, 0.96, 0.86)
		light.shadow_enabled = false
		light.visible = false
		chassis.add_child(light)
		headlights.append(light)

	var wheels: Array[Node3D] = []
	for spec: VehicleConfig.WheelSpec in config.wheels:
		var wheel := MeshFactory.wheel(spec.radius, spec.width)
		wheel.name = "Wheel_%d_%d" % [roundi(spec.position.x * 10.0), roundi(spec.position.z * 10.0)]
		wheels.append(wheel)

	return {"chassis": chassis, "wheels": wheels, "headlights": headlights}
