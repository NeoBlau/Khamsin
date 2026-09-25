class_name SettlementBuilder
extends RefCounted
## Посёлок в трёх измерениях.
##
## До этого посёлок был выровненной площадкой и всплывающим меню: подъезжаешь
## к невидимому кругу в песке — открывается биржа. Всё, что в нём происходило,
## происходило в интерфейсе.
##
## Здесь он собирается по-настоящему: улица, дома со входами и комнатами
## внутри, заправка, мастерская с подъёмником, лавки, навесы, пальмы у воды.
## Состав зависит от того, какие услуги в посёлке есть, — не декоративно, а
## буквально: заправку строит наличие `fuel`, мойку — `wash`.
##
## Раскладка выводится из сида и идентификатора: один и тот же посёлок всегда
## собирается одинаково, и к знакомому дому можно вернуться.

const STREET_WIDTH := 14.0
const SAND_WALL := Color(0.78, 0.71, 0.58)
const MUD_WALL := Color(0.70, 0.60, 0.46)
const WHITE_WALL := Color(0.90, 0.87, 0.80)


## Собирает посёлок целиком и сразу. Годится для тестов и инструментов, но не
## для игры: оазис Дяди Вали — это почти тысяча двести мешей и без малого
## двести миллисекунд, то есть одиннадцать пропущенных кадров ровно в тот
## момент, когда в него въезжаешь.
static func build(settlement: Settlement) -> Dictionary:
	var plan_data := plan(settlement)
	for step: Callable in plan_data["steps"]:
		step.call()
	plan_data.erase("steps")
	return plan_data


## План сборки: готовый корень, список входов и очередь шагов. Шаги надо
## вызывать по одному, растягивая на кадры, — тогда посёлок появляется за
## полсекунды и без просадки.
##
## Порядок шагов фиксирован, и генератор случайностей один на всю очередь:
## раскладка не зависит от того, за сколько кадров её собрали.
static func plan(settlement: Settlement) -> Dictionary:
	var root := Node3D.new()
	root.name = "Settlement_%s" % settlement.id
	root.position = settlement.world_position()
	var doors: Array[Dictionary] = []
	var lights: Array[Node3D] = []
	var steps: Array[Callable] = []

	var rng := Rng.local(Rng.hash_string("settlement:%s" % settlement.id))
	# Улица смотрит в сторону ближайшего соседа: посёлки стоят на дорогах, и
	# въезд логично делать с той стороны, откуда приезжают.
	var street_angle := _street_angle(settlement)
	var palette := _palette(settlement)
	var plots := _plan_plots(settlement, rng, street_angle)

	for plot: Dictionary in plots:
		doors.append(_entrance(settlement, plot))
		steps.append(func() -> void:
			var built := _build_plot(settlement, plot, palette)
			if not built.is_empty():
				root.add_child(built["root"])
				lights.append_array(built.get("lights", []) as Array[Node3D])
		)

	steps.append(func() -> void: _build_street(root, settlement, street_angle, palette, rng, lights))
	for step: Callable in _outskirt_steps(root, settlement, rng):
		steps.append(step)

	return {"root": root, "doors": doors, "lights": lights, "steps": steps}


static func _entrance(settlement: Settlement, plot: Dictionary) -> Dictionary:
	var kind: StringName = plot["kind"]
	var at: Vector3 = plot["at"]
	at.y = _ground(settlement, at)
	return {
		"id": StringName("%s_%s" % [settlement.id, kind]),
		"kind": kind,
		"name": _title(kind, settlement),
		"at": at,
		"facing": plot["facing"],
	}


static func _ground(settlement: Settlement, local: Vector3) -> float:
	var world_x := settlement.position.x + local.x
	var world_z := settlement.position.y + local.z
	return World.height(world_x, world_z) - settlement.ground_height


static func _palette(settlement: Settlement) -> Color:
	match settlement.kind:
		Settlement.Kind.CITY:
			return SAND_WALL
		Settlement.Kind.OASIS:
			return WHITE_WALL
		Settlement.Kind.MINE:
			return Color(0.62, 0.58, 0.54)
		_:
			return MUD_WALL


## Поворот вокруг Y, при котором местная ось +Z смотрит вдоль направления
## `angle` в плане. Вращение на θ отображает +Z в (sin θ, 0, cos θ), а
## направление задано как (cos α, 0, sin α) — отсюда π/2 − α. Ошибка здесь
## незаметна в коде и очень заметна в кадре: улица складывается в зигзаг.
static func _yaw_along(angle: float) -> float:
	return PI * 0.5 - angle


static func _street_angle(settlement: Settlement) -> float:
	var nearest: Settlement = null
	var best := INF
	for other: Settlement in World.settlements:
		if other.id == settlement.id:
			continue
		var distance := other.position.distance_to(settlement.position)
		if distance < best:
			best = distance
			nearest = other
	if nearest == null:
		return 0.0
	var direction := nearest.position - settlement.position
	return atan2(direction.y, direction.x)


## Раскладка участков вдоль улицы. Каждому участку — своё назначение, и
## назначения берутся из услуг посёлка: лишних домов не строим.
static func _plan_plots(settlement: Settlement, rng: RandomNumberGenerator,
		street_angle: float) -> Array[Dictionary]:
	var wanted: Array[StringName] = []
	if settlement.has_service(&"guild") or settlement.contract_slots >= 5:
		wanted.append(&"guild")
	if settlement.has_service(&"repair"):
		wanted.append(&"workshop")
	if settlement.has_service(&"market"):
		wanted.append(&"market")
	if settlement.has_service(&"bunk"):
		wanted.append(&"guesthouse")
	if settlement.has_service(&"post"):
		wanted.append(&"post")
	if settlement.has_service(&"tea"):
		wanted.append(&"majlis")
	if settlement.id == &"wilsacom_oasis":
		wanted.append(&"mansion")
	# Пара жилых домов, чтобы посёлок не состоял из одних учреждений.
	var houses := 5 if settlement.kind == Settlement.Kind.CITY else 2
	for i: int in houses:
		wanted.append(&"house")

	var plots: Array[Dictionary] = []
	var forward := Vector2(cos(street_angle), sin(street_angle))
	var side := Vector2(-forward.y, forward.x)
	var along := -float(wanted.size()) * 0.5 * 22.0
	for i: int in wanted.size():
		var lateral := (STREET_WIDTH * 0.5 + 9.0) * (1.0 if i % 2 == 0 else -1.0)
		var jitter := rng.randf_range(-2.0, 2.0)
		var spot := forward * (along + jitter) + side * lateral
		plots.append({
			"kind": wanted[i],
			"at": Vector3(spot.x, 0.0, spot.y),
			"facing": _yaw_along(street_angle) + (PI if i % 2 == 0 else 0.0),
		})
		along += 22.0
	return plots


static func _build_plot(settlement: Settlement, plot: Dictionary, palette: Color) -> Dictionary:
	var kind: StringName = plot["kind"]
	var rooms := _rooms_for(kind, settlement)
	if rooms.is_empty():
		return {}
	var built := BuildingBuilder.build(rooms, palette)
	var root: Node3D = built["root"]
	var at: Vector3 = plot["at"]
	at.y = _ground(settlement, at)
	root.position = at
	root.rotation.y = plot["facing"]

	_add_roof(root, rooms, palette)
	_add_sign(root, kind, settlement, rooms)
	return {"root": root, "lights": built.get("lights", [])}


## Комнаты по назначению здания. Здесь же — единственное место, где задаётся
## обстановка: снаружи дом отличается вывеской, внутри — тем, что в нём есть.
static func _rooms_for(kind: StringName, settlement: Settlement) -> Array[BuildingBuilder.Room]:
	var rooms: Array[BuildingBuilder.Room] = []

	var make := func(id: StringName, name: String, size: Vector3, at: Vector3,
			props: Array[StringName], doors: Array[StringName],
			windows: Array[StringName]) -> BuildingBuilder.Room:
		var room := BuildingBuilder.Room.new()
		room.id = id
		room.name = name
		room.size = size
		room.centre = at + Vector3(0.0, size.y * 0.5, 0.0)
		room.props = props
		room.doors = doors
		room.windows = windows
		return room

	match kind:
		&"guild":
			rooms.append(make.call(&"hall", "Контора гильдии", Vector3(9.0, 3.4, 7.0),
				Vector3.ZERO, [&"desk", &"shelf", &"carpet"] as Array[StringName],
				[&"south"] as Array[StringName], [&"east", &"west"] as Array[StringName]))
		&"workshop":
			rooms.append(make.call(&"bay", "Мастерская", Vector3(11.0, 4.4, 9.0),
				Vector3.ZERO, [&"lift", &"workbench", &"tool_board", &"tyre_stack"] as Array[StringName],
				[&"south"] as Array[StringName], [&"north"] as Array[StringName]))
		&"market":
			rooms.append(make.call(&"shop", "Лавка", Vector3(8.0, 3.2, 6.0),
				Vector3.ZERO, [&"counter", &"shelf", &"crates"] as Array[StringName],
				[&"south"] as Array[StringName], [&"east"] as Array[StringName]))
		&"guesthouse":
			rooms.append(make.call(&"room", "Ночлежка", Vector3(7.0, 3.0, 6.0),
				Vector3.ZERO, [&"bed", &"low_table", &"carpet"] as Array[StringName],
				[&"south"] as Array[StringName], [&"west"] as Array[StringName]))
		&"post":
			rooms.append(make.call(&"hall", "DubaiLux — выдача", Vector3(13.0, 4.6, 10.0),
				Vector3.ZERO, [&"counter", &"parcel_wall", &"boxes", &"desk"] as Array[StringName],
				[&"south"] as Array[StringName], [&"east", &"west"] as Array[StringName]))
		&"majlis":
			rooms.append(make.call(&"majlis", "Меджлис", Vector3(9.0, 3.4, 8.0),
				Vector3.ZERO, [&"cushions", &"carpet", &"low_table", &"tea_set"] as Array[StringName],
				[&"south"] as Array[StringName], [&"north", &"east"] as Array[StringName]))
		&"mansion":
			# Особняк Дяди Вали: два этажа и зал, в котором стоит всё, что
			# приехало из DubaiLux и не поместилось в прихожей.
			rooms.append(make.call(&"hall", "Особняк — зал", Vector3(14.0, 4.6, 11.0),
				Vector3.ZERO, [&"carpet", &"cushions", &"tv_wall", &"chandelier", &"boxes"] as Array[StringName],
				[&"south"] as Array[StringName], [&"east", &"west"] as Array[StringName]))
			rooms.append(make.call(&"upper", "Особняк — второй этаж", Vector3(14.0, 3.4, 11.0),
				Vector3(0.0, 4.6, 0.0), [&"bed", &"shelf", &"low_table"] as Array[StringName],
				[] as Array[StringName], [&"south", &"east"] as Array[StringName]))
		_:
			rooms.append(make.call(&"home", "Дом", Vector3(7.0, 3.0, 6.0),
				Vector3.ZERO, [&"carpet", &"low_table", &"bed"] as Array[StringName],
				[&"south"] as Array[StringName], [&"east"] as Array[StringName]))
	return rooms


static func _title(kind: StringName, settlement: Settlement) -> String:
	match kind:
		&"guild": return "Контора гильдии"
		&"workshop": return "Мастерская"
		&"market": return "Лавка"
		&"guesthouse": return "Ночлег"
		&"post": return "DubaiLux"
		&"majlis": return "Меджлис"
		&"mansion": return "Особняк Дяди Вали"
		_: return "Дом"


## Крыша: плоская, с парапетом. Плоские крыши здесь не стилизация, на них
## спят летом и сушат бельё, и парапет по краю — первое, что это выдаёт.
static func _add_roof(root: Node3D, rooms: Array[BuildingBuilder.Room], palette: Color) -> void:
	var top := -INF
	var span := Vector3.ZERO
	var centre := Vector3.ZERO
	for room: BuildingBuilder.Room in rooms:
		var room_top := room.centre.y + room.size.y * 0.5
		if room_top > top:
			top = room_top
			span = room.size
			centre = room.centre
	if top == -INF:
		return
	var slab := MeshFactory.panel(
		Vector3(span.x + 0.5, 0.22, span.z + 0.5), palette.darkened(0.08),
		0.95, 0.0, 0.04
	)
	slab.position = Vector3(centre.x, top + 0.18, centre.z)
	root.add_child(slab)
	for side: int in 4:
		var along_x := side < 2
		var sign_value := 1.0 if side % 2 == 0 else -1.0
		var size := Vector3(span.x + 0.5, 0.42, 0.16) if along_x \
			else Vector3(0.16, 0.42, span.z + 0.5)
		var offset := Vector3(0.0, 0.0, sign_value * (span.z + 0.5) * 0.5) if along_x \
			else Vector3(sign_value * (span.x + 0.5) * 0.5, 0.0, 0.0)
		var parapet := MeshFactory.panel(size, palette, 0.95, 0.0, 0.03)
		parapet.position = Vector3(centre.x, top + 0.5, centre.z) + offset
		root.add_child(parapet)


static func _add_sign(root: Node3D, kind: StringName, settlement: Settlement,
		rooms: Array[BuildingBuilder.Room]) -> void:
	if rooms.is_empty():
		return
	var room := rooms[0]
	var board := MeshFactory.panel(
		Vector3(room.size.x * 0.5, 0.5, 0.08),
		Color(0.24, 0.20, 0.16), 0.85, 0.0, 0.02
	)
	board.position = Vector3(0.0, room.centre.y + room.size.y * 0.5 + 0.4, room.size.z * 0.5 + 0.12)
	root.add_child(board)
	# Три полосы вместо надписи: текста в процедурной геометрии нет, а
	# вывеска без ничего читается как пустой щит.
	var accent := Color(0.85, 0.70, 0.38)
	if kind == &"post":
		accent = Color(0.35, 0.62, 0.86)
	elif kind == &"mansion":
		accent = Color(0.86, 0.74, 0.28)
	for i: int in 3:
		var stripe := MeshFactory.panel(
			Vector3(room.size.x * (0.30 - float(i) * 0.07), 0.07, 0.03), accent, 0.6, 0.1, 0.01
		)
		stripe.position = board.position + Vector3(
			-room.size.x * 0.06, 0.14 - float(i) * 0.14, 0.06
		)
		root.add_child(stripe)


## Улица: полотно, столбы с фонарями, заправка и мойка, если они тут есть.
static func _build_street(root: Node3D, settlement: Settlement, angle: float,
		palette: Color, rng: RandomNumberGenerator, lights: Array[Node3D]) -> void:
	var forward := Vector3(cos(angle), 0.0, sin(angle))
	var length := 26.0 * 4.0
	# Полотно из сегментов, а не одной плитой: одна плита на сто метров
	# повисает над любым уклоном, и въезд в посёлок выглядит как пандус в
	# никуда.
	var segments := 16
	for i: int in segments:
		var along := (float(i) + 0.5) / float(segments) * length - length * 0.5
		var at := forward * along
		var piece := MeshFactory.panel(
			Vector3(STREET_WIDTH, 0.12, length / float(segments) * 1.06),
			Color(0.58, 0.53, 0.45), 0.96, 0.0, 0.02
		)
		piece.position = at + Vector3(0.0, _ground(settlement, at) + 0.06, 0.0)
		piece.rotation.y = _yaw_along(angle)
		root.add_child(piece)

	var side := Vector3(-forward.z, 0.0, forward.x)
	for i: int in 6:
		var along := (float(i) / 5.0 - 0.5) * length * 0.8
		var lateral := (STREET_WIDTH * 0.5 + 1.2) * (1.0 if i % 2 == 0 else -1.0)
		var post := MeshFactory.tube(0.09, 4.2, Color(0.32, 0.30, 0.28), Vector3.UP, 0.7, 0.4, 6)
		var post_at := forward * along + side * lateral
		post.position = post_at + Vector3(0.0, _ground(settlement, post_at) + 2.1, 0.0)
		root.add_child(post)
		var lamp := OmniLight3D.new()
		lamp.position = post.position + Vector3(0.0, 2.1, 0.0)
		lamp.light_color = Color(1.0, 0.84, 0.58)
		lamp.light_energy = 2.4
		lamp.omni_range = 16.0
		lamp.shadow_enabled = false
		lamp.visible = false
		root.add_child(lamp)
		lights.append(lamp)

	if settlement.has_service(&"fuel"):
		var fuel_at := forward * (-length * 0.42) + side * (STREET_WIDTH * 0.5 + 5.0)
		fuel_at.y = _ground(settlement, fuel_at)
		_build_fuel(root, fuel_at, angle)
	if settlement.has_service(&"wash") or settlement.has_service(&"wash_full"):
		var wash_at := forward * (length * 0.40) + side * (STREET_WIDTH * 0.5 + 6.0)
		wash_at.y = _ground(settlement, wash_at)
		_build_wash_bay(root, wash_at, angle, settlement.has_service(&"wash_full"))


static func _build_fuel(root: Node3D, at: Vector3, angle: float) -> void:
	var bay := Node3D.new()
	bay.name = "FuelBay"
	bay.position = at
	bay.rotation.y = _yaw_along(angle)
	root.add_child(bay)
	# Навес на четырёх столбах — силуэт заправки узнаётся именно по нему.
	var canopy := MeshFactory.panel(Vector3(9.0, 0.3, 6.0), Color(0.86, 0.84, 0.80), 0.8, 0.1, 0.05)
	canopy.position = Vector3(0.0, 4.6, 0.0)
	bay.add_child(canopy)
	for x: float in [-4.0, 4.0]:
		for z: float in [-2.5, 2.5]:
			var post := MeshFactory.tube(0.14, 4.6, Color(0.80, 0.78, 0.74), Vector3.UP, 0.7, 0.3, 8)
			post.position = Vector3(x, 2.3, z)
			bay.add_child(post)
	for i: int in 2:
		var pump := MeshFactory.panel(Vector3(0.7, 1.7, 0.5), Color(0.72, 0.28, 0.20), 0.6, 0.2, 0.04)
		pump.position = Vector3(-1.6 + float(i) * 3.2, 0.85, 0.0)
		bay.add_child(pump)
		var head := MeshFactory.panel(Vector3(0.6, 0.4, 0.06), Color(0.10, 0.12, 0.14), 0.3, 0.2, 0.02)
		head.position = pump.position + Vector3(0.0, 0.55, 0.28)
		bay.add_child(head)
	var tank := MeshFactory.tube(1.3, 5.0, Color(0.72, 0.70, 0.66), Vector3.RIGHT, 0.6, 0.5, 14)
	tank.position = Vector3(0.0, 1.4, -4.6)
	bay.add_child(tank)


static func _build_wash_bay(root: Node3D, at: Vector3, angle: float, full: bool) -> void:
	var bay := Node3D.new()
	bay.name = "WashBay"
	bay.position = at
	bay.rotation.y = _yaw_along(angle)
	root.add_child(bay)
	var slab := MeshFactory.panel(Vector3(7.0, 0.14, 9.0), Color(0.62, 0.62, 0.60), 0.85, 0.0, 0.03)
	slab.position = Vector3(0.0, 0.07, 0.0)
	bay.add_child(slab)
	for side: float in [-1.0, 1.0]:
		var wall := MeshFactory.panel(Vector3(0.2, 2.6, 9.0), Color(0.80, 0.80, 0.78), 0.9, 0.0, 0.03)
		wall.position = Vector3(side * 3.4, 1.3, 0.0)
		bay.add_child(wall)
	# Стойка с шлангом.
	var post := MeshFactory.tube(0.12, 2.4, Color(0.50, 0.50, 0.48), Vector3.UP, 0.7, 0.4, 8)
	post.position = Vector3(2.6, 1.2, -3.2)
	bay.add_child(post)
	if full:
		# Щётки на кронштейне: то, чем снимают верблюжьи плевки.
		for i: int in 3:
			var brush := MeshFactory.panel(Vector3(0.18, 1.1, 0.18), Color(0.28, 0.42, 0.62), 0.95, 0.0, 0.03)
			brush.position = Vector3(2.2, 1.4, -1.6 + float(i) * 1.1)
			bay.add_child(brush)
		var water := MeshFactory.tube(0.8, 2.0, Color(0.50, 0.62, 0.68), Vector3.UP, 0.5, 0.3, 12)
		water.position = Vector3(-2.6, 1.0, 3.4)
		bay.add_child(water)


## Окраина: пальмы у воды, стены, брошенная техника. То, что делает посёлок
## обжитым, а не выставленным по линейке.
##
## Возвращается очередью шагов, а не одной функцией: в оазисе четырнадцать
## пальм, и каждая — полсотни панелей. Одним куском это и есть та самая
## просадка, ради которой всё разбиралось.
static func _outskirt_steps(root: Node3D, settlement: Settlement,
		rng: RandomNumberGenerator) -> Array[Callable]:
	var steps: Array[Callable] = []

	if settlement.kind == Settlement.Kind.OASIS:
		# Пальмы растут у воды, а не по всему посёлку: в пустыне дерево стоит
		# ровно там, где до воды дотягивается корень. Две трети — кольцом
		# вокруг пруда, остальные рассыпаны по краю.
		var pool_centre := Vector3(0.0, 0.0, -46.0)
		for i: int in 30:
			var near_water := i < 20
			var angle := rng.randf() * TAU
			var distance := rng.randf_range(13.0, 26.0) if near_water \
				else rng.randf_range(34.0, 86.0)
			var origin := pool_centre if near_water else Vector3.ZERO
			var scale_value := rng.randf_range(1.15, 1.85) if near_water \
				else rng.randf_range(0.9, 1.4)
			var seed_value := rng.randi()
			steps.append(func() -> void:
				var palm_at := origin + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
				palm_at.y = _ground(settlement, palm_at)
				root.add_child(PropBuilder.palm(palm_at, scale_value, seed_value))
			)
		# Трава по кромке воды: без неё пруд выглядит вырезанным в песке.
		for i: int in 26:
			var angle := rng.randf() * TAU
			var distance := rng.randf_range(9.0, 15.0)
			var tuft_seed := rng.randi()
			steps.append(func() -> void:
				var at := pool_centre + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance * 0.75)
				at.y = _ground(settlement, at)
				root.add_child(_grass_tuft(at, tuft_seed))
			)
		steps.append(func() -> void: _build_pool(root, settlement))

	var fence_angle := rng.randf() * TAU
	steps.append(func() -> void: _build_fence(root, settlement, fence_angle))

	var crate_spots: Array[Vector3] = []
	var crate_turns: Array[float] = []
	for i: int in 5:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(34.0, 70.0)
		crate_spots.append(Vector3(cos(angle) * distance, 0.0, sin(angle) * distance))
		crate_turns.append(rng.randf() * TAU)
	steps.append(func() -> void:
		for i: int in crate_spots.size():
			var crate := MeshFactory.panel(
				Vector3(1.0, 0.8, 1.2), Color(0.60, 0.50, 0.36), 0.95, 0.0, 0.04
			)
			var at: Vector3 = crate_spots[i]
			crate.position = at + Vector3(0.0, _ground(settlement, at) + 0.4, 0.0)
			crate.rotation.y = crate_turns[i]
			root.add_child(crate)
	)
	return steps


## Куст осоки у воды. Пять листьев враскид — узнаётся как трава и стоит
## пять панелей.
static func _grass_tuft(at: Vector3, seed_value: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Grass"
	root.position = at
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i: int in 5:
		var blade := MeshFactory.panel(
			Vector3(0.07, rng.randf_range(0.5, 1.1), 0.07),
			Color(0.30, 0.44, 0.20).lightened(rng.randf() * 0.18), 0.95, 0.0, 0.02
		)
		blade.position = Vector3(rng.randfn(0.0, 0.14), blade.mesh.get_aabb().size.y * 0.45, rng.randfn(0.0, 0.14))
		blade.rotation = Vector3(rng.randfn(0.0, 0.25), rng.randf() * TAU, rng.randfn(0.0, 0.25))
		root.add_child(blade)
	return root


## Вода: то, ради чего оазис и существует.
static func _build_pool(root: Node3D, settlement: Settlement) -> void:
	var pool_at := Vector3(0.0, 0.0, -46.0)
	var base := _ground(settlement, pool_at)
	var pool := MeshFactory.glass(Vector3(34.0, 0.3, 24.0), Color(0.24, 0.46, 0.50, 0.72))
	pool.position = pool_at + Vector3(0.0, base + 0.1, 0.0)
	root.add_child(pool)
	for side: int in 4:
		var along_x := side < 2
		var sign_value := 1.0 if side % 2 == 0 else -1.0
		var kerb := MeshFactory.panel(
			Vector3(35.0, 0.5, 0.8) if along_x else Vector3(0.8, 0.5, 25.0),
			Color(0.82, 0.78, 0.70), 0.9, 0.0, 0.03
		)
		kerb.position = Vector3(0.0, base + 0.2, -46.0) + (
			Vector3(0.0, 0.0, sign_value * 12.4) if along_x
			else Vector3(sign_value * 17.4, 0.0, 0.0)
		)
		root.add_child(kerb)


## Ограда из плит с той стороны, откуда приходит песок.
static func _build_fence(root: Node3D, settlement: Settlement, angle: float) -> void:
	var spot := Vector3(cos(angle) * 62.0, 0.0, sin(angle) * 62.0)
	var side := Vector3(-sin(angle), 0.0, cos(angle))
	for i: int in 9:
		var t := (float(i) / 8.0 - 0.5) * 46.0
		var slab := MeshFactory.panel(
			Vector3(5.4, 2.2, 0.26), Color(0.70, 0.66, 0.58), 0.95, 0.0, 0.04
		)
		var at := spot + side * t
		slab.position = at + Vector3(0.0, _ground(settlement, at) + 1.1, 0.0)
		slab.rotation.y = _yaw_along(angle)
		root.add_child(slab)
