class_name BuildingBuilder
extends RefCounted
## Здания и их внутренности.
##
## Дом строится изнутри наружу: сначала комнаты, потом стены вокруг них. Так
## интерьер гарантированно соответствует габаритам снаружи — нельзя получить
## особняк, в котором комнат больше, чем места.
##
## Оконные проёмы вырезаются не булевой операцией, а тем, что стена собирается
## из кусков: перемычка сверху, подоконник снизу, простенки по бокам. Дороже
## в коде, зато геометрия остаётся выпуклой и предсказуемой, а это важно для
## коллизии: игрок не должен застревать в дверном косяке.

const WALL := Color(0.80, 0.73, 0.60)
const WALL_INNER := Color(0.86, 0.82, 0.74)
const FLOOR := Color(0.55, 0.47, 0.38)
const ROOF := Color(0.66, 0.58, 0.46)
const WOOD := Color(0.36, 0.25, 0.16)
const MARBLE := Color(0.90, 0.88, 0.84)
const WALL_THICKNESS := 0.28
const DOOR_WIDTH := 1.1
const DOOR_HEIGHT := 2.1


## Описание комнаты: где, какого размера и что в ней стоит.
class Room:
	extends RefCounted
	var id: StringName = &"room"
	var name: String = "Комната"
	var centre: Vector3 = Vector3.ZERO
	var size: Vector3 = Vector3(6.0, 3.0, 6.0)
	var floor_colour: Color = FLOOR
	var wall_colour: Color = WALL_INNER
	## Стороны, где в стене проём: &"north", &"south", &"east", &"west".
	var doors: Array[StringName] = []
	var windows: Array[StringName] = []
	var props: Array[StringName] = []
	var light: Color = Color(1.0, 0.86, 0.66)
	var light_energy: float = 1.2


## Собирает здание из комнат. Возвращает {root, rooms, lights, doors}.
static func build(rooms: Array[Room], outer_colour: Color = WALL) -> Dictionary:
	var root := Node3D.new()
	root.name = "Building"
	var lights: Array[OmniLight3D] = []
	var door_nodes: Array[Node3D] = []

	for room: Room in rooms:
		var node := _build_room(room, outer_colour)
		root.add_child(node["root"])
		lights.append_array(node["lights"] as Array[OmniLight3D])
		door_nodes.append_array(node["doors"] as Array[Node3D])

	return {"root": root, "rooms": rooms, "lights": lights, "doors": door_nodes}


static func _build_room(room: Room, outer_colour: Color) -> Dictionary:
	var root := Node3D.new()
	root.name = "Room_%s" % room.id
	root.position = room.centre
	var lights: Array[OmniLight3D] = []
	var doors: Array[Node3D] = []
	var half := room.size * 0.5

	# Пол и потолок.
	var floor_panel := MeshFactory.panel(
		Vector3(room.size.x, 0.16, room.size.z), room.floor_colour, 0.92, 0.0, 0.03
	)
	floor_panel.position = Vector3(0.0, -half.y - 0.08, 0.0)
	root.add_child(floor_panel)
	_add_static_body(root, floor_panel.position, Vector3(room.size.x, 0.16, room.size.z))

	var ceiling := MeshFactory.panel(
		Vector3(room.size.x, 0.14, room.size.z), room.wall_colour.darkened(0.12), 0.95, 0.0, 0.02
	)
	ceiling.position = Vector3(0.0, half.y + 0.07, 0.0)
	root.add_child(ceiling)

	# Четыре стены. Каждая знает, есть ли в ней дверь и окно.
	var sides := {
		&"north": Vector3(0.0, 0.0, -half.z),
		&"south": Vector3(0.0, 0.0, half.z),
		&"west": Vector3(-half.x, 0.0, 0.0),
		&"east": Vector3(half.x, 0.0, 0.0),
	}
	for side: StringName in sides:
		var along_x := side == &"north" or side == &"south"
		var length := room.size.x if along_x else room.size.z
		var at: Vector3 = sides[side]
		var has_door := room.doors.has(side)
		var has_window := room.windows.has(side)
		var wall := _build_wall(
			length, room.size.y, along_x, has_door, has_window, outer_colour, room.wall_colour
		)
		wall.position = at
		root.add_child(wall)
		if has_door:
			doors.append(wall)
		_add_wall_collision(root, at, length, room.size.y, along_x, has_door)

	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(0.0, half.y - 0.35, 0.0)
	lamp.light_color = room.light
	lamp.light_energy = room.light_energy
	lamp.omni_range = maxf(room.size.x, room.size.z) * 1.1
	lamp.shadow_enabled = false
	root.add_child(lamp)
	lights.append(lamp)

	for prop: StringName in room.props:
		var built := PropBuilder.build(prop, room.size)
		if built != null:
			root.add_child(built)

	return {"root": root, "lights": lights, "doors": doors}


## Стена как набор кусков. Проём получается из того, что кусков вокруг него
## четыре, а не из вырезания дыры: геометрия остаётся выпуклой, и игрок не
## цепляется за косяк.
static func _build_wall(length: float, height: float, along_x: bool, door: bool,
		window: bool, outer: Color, inner: Color) -> Node3D:
	var wall := Node3D.new()
	wall.name = "Wall"
	var thickness := WALL_THICKNESS

	var piece := func(width: float, tall: float, offset_along: float, offset_up: float) -> void:
		if width <= 0.01 or tall <= 0.01:
			return
		var size := Vector3(width, tall, thickness) if along_x \
			else Vector3(thickness, tall, width)
		var panel := MeshFactory.panel(size, outer, 0.94, 0.0, 0.04)
		panel.position = Vector3(offset_along, offset_up, 0.0) if along_x \
			else Vector3(0.0, offset_up, offset_along)
		wall.add_child(panel)

	var gap := 0.0
	var gap_height := 0.0
	var gap_bottom := 0.0
	if door:
		gap = DOOR_WIDTH
		gap_height = DOOR_HEIGHT
		gap_bottom = -height * 0.5
	elif window:
		gap = length * 0.42
		gap_height = height * 0.36
		gap_bottom = -height * 0.5 + height * 0.42

	if gap <= 0.0:
		piece.call(length, height, 0.0, 0.0)
		return wall

	var side_width := (length - gap) * 0.5
	piece.call(side_width, height, -(gap + side_width) * 0.5, 0.0)
	piece.call(side_width, height, (gap + side_width) * 0.5, 0.0)
	# Перемычка над проёмом.
	var lintel := height * 0.5 - (gap_bottom + gap_height)
	piece.call(gap, lintel, 0.0, (gap_bottom + gap_height) + lintel * 0.5)
	# Подоконник снизу — у двери его нет.
	var sill := gap_bottom - (-height * 0.5)
	piece.call(gap, sill, 0.0, -height * 0.5 + sill * 0.5)

	if window:
		var glass_size := Vector3(gap, gap_height, 0.04) if along_x \
			else Vector3(0.04, gap_height, gap)
		var glass := MeshFactory.glass(glass_size, Color(0.62, 0.70, 0.74, 0.20))
		glass.position = Vector3(0.0, gap_bottom + gap_height * 0.5, 0.0)
		wall.add_child(glass)
	return wall


static func _add_static_body(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)


## Коллизия стены. Проём оставляем свободным, иначе в дверь не пройти —
## и это ровно тот случай, когда снаружи всё выглядит правильно.
static func _add_wall_collision(parent: Node3D, at: Vector3, length: float, height: float,
		along_x: bool, door: bool) -> void:
	if not door:
		var size := Vector3(length, height, WALL_THICKNESS) if along_x \
			else Vector3(WALL_THICKNESS, height, length)
		_add_static_body(parent, at, size)
		return
	var side_width := (length - DOOR_WIDTH) * 0.5
	for sign_value: float in [-1.0, 1.0]:
		var offset := sign_value * (DOOR_WIDTH + side_width) * 0.5
		var size := Vector3(side_width, height, WALL_THICKNESS) if along_x \
			else Vector3(WALL_THICKNESS, height, side_width)
		var spot := at + (Vector3(offset, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, offset))
		_add_static_body(parent, spot, size)
	# Перемычка над дверью — по ней ходить нельзя, но голова в неё упирается.
	var lintel := height - DOOR_HEIGHT
	if lintel > 0.05:
		var size := Vector3(DOOR_WIDTH, lintel, WALL_THICKNESS) if along_x \
			else Vector3(WALL_THICKNESS, lintel, DOOR_WIDTH)
		_add_static_body(parent, at + Vector3(0.0, height * 0.5 - lintel * 0.5, 0.0), size)
