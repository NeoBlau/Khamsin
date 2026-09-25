class_name PropBuilder
extends RefCounted
## Обстановка: мебель, ящики, пальмы, всё, что стоит внутри и снаружи зданий.
##
## Пустая комната с четырьмя стенами читается как недоделанная, сколько бы
## труда ни было вложено в сами стены. Реквизит стоит дёшево — десяток панелей
## на предмет — и делает больше для ощущения места, чем вдвое более подробная
## архитектура.
##
## Каждый предмет знает габарит комнаты, в которую его ставят, и расставляется
## относительно него: один и тот же «стол» уместен и в каморке, и в зале.

const WOOD := Color(0.38, 0.26, 0.16)
const WOOD_LIGHT := Color(0.55, 0.40, 0.25)
const CLOTH := Color(0.45, 0.22, 0.20)
const METAL := Color(0.44, 0.44, 0.42)
const DARK := Color(0.16, 0.15, 0.15)
const PAPER := Color(0.82, 0.78, 0.68)
const GREEN := Color(0.24, 0.42, 0.20)


static func build(kind: StringName, room: Vector3) -> Node3D:
	var half := room * 0.5
	match kind:
		&"table":
			return _table(Vector3(0.0, -half.y, 0.0))
		&"low_table":
			return _low_table(Vector3(0.0, -half.y, 0.0))
		&"carpet":
			return _carpet(Vector3(0.0, -half.y + 0.01, 0.0), room)
		&"cushions":
			return _cushions(room)
		&"bed":
			return _bed(Vector3(half.x - 1.3, -half.y, -half.z + 1.2))
		&"shelf":
			return _shelf(Vector3(-half.x + 0.4, -half.y, 0.0))
		&"counter":
			return _counter(Vector3(0.0, -half.y, -half.z + 1.6), room)
		&"parcel_wall":
			return _parcel_wall(Vector3(0.0, -half.y, half.z - 0.5), room)
		&"boxes":
			return _boxes(Vector3(half.x - 1.0, -half.y, half.z - 1.0))
		&"workbench":
			return _workbench(Vector3(-half.x + 1.0, -half.y, 0.0), room)
		&"tool_board":
			return _tool_board(Vector3(0.0, 0.2, -half.z + 0.25), room)
		&"tyre_stack":
			return _tyre_stack(Vector3(half.x - 1.2, -half.y, -half.z + 1.2))
		&"fountain":
			return _fountain(Vector3(0.0, -half.y, 0.0))
		&"palm":
			return palm(Vector3.ZERO, 1.0)
		&"tv_wall":
			return _tv_wall(Vector3(0.0, 0.3, -half.z + 0.3), room)
		&"chandelier":
			return _chandelier(Vector3(0.0, half.y - 0.5, 0.0))
		&"desk":
			return _desk(Vector3(0.0, -half.y, -half.z + 1.4))
		&"lift":
			return _lift(Vector3(0.0, -half.y, 0.0), room)
		&"crates":
			return _crates(Vector3(-half.x + 1.2, -half.y, half.z - 1.4))
		&"tea_set":
			return _tea_set(Vector3(0.0, -half.y + 0.42, 0.0))
		_:
			return null


static func _node(name: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = name
	node.position = at
	return node


static func _panel(parent: Node3D, size: Vector3, colour: Color, at: Vector3,
		roughness: float = 0.85, metallic: float = 0.0) -> MeshInstance3D:
	var panel := MeshFactory.panel(size, colour, roughness, metallic, minf(0.02, size.min_axis_index()))
	panel.position = at
	parent.add_child(panel)
	return panel


# --- Мебель -----------------------------------------------------------------


static func _table(at: Vector3) -> Node3D:
	var root := _node("Table", at)
	_panel(root, Vector3(1.6, 0.07, 0.9), WOOD_LIGHT, Vector3(0.0, 0.76, 0.0), 0.7)
	for x: float in [-0.7, 0.7]:
		for z: float in [-0.35, 0.35]:
			_panel(root, Vector3(0.08, 0.74, 0.08), WOOD, Vector3(x, 0.37, z), 0.8)
	for side: float in [-1.0, 1.0]:
		var chair := _node("Chair", Vector3(0.0, 0.0, side * 0.85))
		_panel(chair, Vector3(0.46, 0.06, 0.44), WOOD_LIGHT, Vector3(0.0, 0.45, 0.0), 0.8)
		_panel(chair, Vector3(0.46, 0.52, 0.06), WOOD, Vector3(0.0, 0.72, side * 0.19), 0.8)
		for x: float in [-0.18, 0.18]:
			for z: float in [-0.18, 0.18]:
				_panel(chair, Vector3(0.05, 0.44, 0.05), WOOD, Vector3(x, 0.22, z), 0.85)
		root.add_child(chair)
	return root


static func _low_table(at: Vector3) -> Node3D:
	var root := _node("LowTable", at)
	_panel(root, Vector3(1.1, 0.06, 1.1), WOOD_LIGHT, Vector3(0.0, 0.40, 0.0), 0.6)
	_panel(root, Vector3(0.22, 0.38, 0.22), WOOD, Vector3(0.0, 0.20, 0.0), 0.8)
	return root


static func _carpet(at: Vector3, room: Vector3) -> Node3D:
	var root := _node("Carpet", at)
	var size := Vector3(minf(room.x - 1.2, 4.6), 0.03, minf(room.z - 1.2, 3.4))
	_panel(root, size, Color(0.48, 0.18, 0.17), Vector3.ZERO, 0.98)
	# Кайма и узор: ковёр без рисунка читается как крашеный пол.
	_panel(root, Vector3(size.x * 0.88, 0.035, size.z * 0.78), Color(0.62, 0.26, 0.20), Vector3(0.0, 0.004, 0.0), 0.98)
	for i: int in 3:
		var t := (float(i) - 1.0) * size.x * 0.26
		_panel(root, Vector3(size.x * 0.12, 0.04, size.z * 0.42), Color(0.78, 0.66, 0.40),
			Vector3(t, 0.008, 0.0), 0.98)
	return root


static func _cushions(room: Vector3) -> Node3D:
	var half := room * 0.5
	var root := _node("Cushions", Vector3(0.0, -half.y, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	# Вдоль стен, как в настоящем меджлисе: сидят по периметру, а не вокруг стола.
	for i: int in 8:
		var along := (float(i) / 7.0 - 0.5) * (room.x - 1.4)
		var side := -1.0 if i < 4 else 1.0
		if i >= 4:
			along = (float(i - 4) / 3.0 - 0.5) * (room.x - 1.4)
		_panel(root, Vector3(0.62, 0.18, 0.52),
			CLOTH.lightened(rng.randf() * 0.18),
			Vector3(along, 0.09, side * (half.z - 0.55)), 0.97)
		_panel(root, Vector3(0.58, 0.40, 0.16),
			CLOTH.darkened(0.1),
			Vector3(along, 0.30, side * (half.z - 0.32)), 0.97)
	return root


static func _bed(at: Vector3) -> Node3D:
	var root := _node("Bed", at)
	_panel(root, Vector3(1.1, 0.34, 2.0), WOOD, Vector3(0.0, 0.17, 0.0), 0.85)
	_panel(root, Vector3(1.04, 0.16, 1.94), Color(0.78, 0.74, 0.66), Vector3(0.0, 0.42, 0.0), 0.96)
	_panel(root, Vector3(0.62, 0.12, 0.34), Color(0.88, 0.86, 0.80), Vector3(0.0, 0.54, -0.72), 0.96)
	_panel(root, Vector3(1.1, 0.5, 0.08), WOOD, Vector3(0.0, 0.45, -1.02), 0.85)
	return root


static func _shelf(at: Vector3) -> Node3D:
	var root := _node("Shelf", at)
	_panel(root, Vector3(0.36, 2.0, 1.6), WOOD, Vector3(0.0, 1.0, 0.0), 0.88)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7311
	for level: int in 4:
		var y := 0.45 + float(level) * 0.45
		_panel(root, Vector3(0.40, 0.04, 1.6), WOOD_LIGHT, Vector3(0.0, y, 0.0), 0.8)
		for i: int in 5:
			if rng.randf() < 0.3:
				continue
			_panel(root, Vector3(0.22, 0.26, 0.10 + rng.randf() * 0.08),
				Color(0.5 + rng.randf() * 0.3, 0.42, 0.3),
				Vector3(0.0, y + 0.15, -0.62 + float(i) * 0.31), 0.9)
	return root


static func _desk(at: Vector3) -> Node3D:
	var root := _node("Desk", at)
	_panel(root, Vector3(1.5, 0.06, 0.75), WOOD_LIGHT, Vector3(0.0, 0.74, 0.0), 0.7)
	_panel(root, Vector3(0.5, 0.68, 0.7), WOOD, Vector3(-0.45, 0.36, 0.0), 0.85)
	_panel(root, Vector3(0.06, 0.70, 0.7), WOOD, Vector3(0.72, 0.36, 0.0), 0.85)
	_panel(root, Vector3(0.28, 0.02, 0.2), PAPER, Vector3(0.2, 0.78, 0.05), 0.95)
	return root


# --- Почта ------------------------------------------------------------------


static func _counter(at: Vector3, room: Vector3) -> Node3D:
	var root := _node("Counter", at)
	var width := minf(room.x - 1.6, 4.2)
	_panel(root, Vector3(width, 1.05, 0.7), WOOD, Vector3(0.0, 0.52, 0.0), 0.85)
	_panel(root, Vector3(width + 0.16, 0.08, 0.86), WOOD_LIGHT, Vector3(0.0, 1.08, 0.0), 0.6)
	# Табличка «выдача».
	_panel(root, Vector3(0.7, 0.22, 0.03), Color(0.92, 0.88, 0.78), Vector3(0.0, 1.45, -0.3), 0.8)
	return root


## Стеллаж с посылками. Главный предмет DubaiLux: по нему видно, что сюда
## приходит всё подряд и разбирать это никто не успевает.
static func _parcel_wall(at: Vector3, room: Vector3) -> Node3D:
	var root := _node("Parcels", at)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var width := minf(room.x - 1.0, 6.0)
	var columns := maxi(3, int(width / 0.9))
	for column: int in columns:
		var x := (float(column) / float(maxi(columns - 1, 1)) - 0.5) * (width - 0.9)
		_panel(root, Vector3(0.06, 2.2, 0.7), METAL, Vector3(x - 0.42, 1.1, 0.0), 0.7, 0.4)
		for level: int in 5:
			var y := 0.3 + float(level) * 0.44
			_panel(root, Vector3(0.84, 0.04, 0.7), METAL, Vector3(x, y, 0.0), 0.7, 0.4)
			var boxes := rng.randi_range(0, 2)
			for i: int in boxes:
				var box_size := Vector3(
					0.22 + rng.randf() * 0.18, 0.18 + rng.randf() * 0.14, 0.22 + rng.randf() * 0.2
				)
				_panel(root, box_size, Color(0.72, 0.64, 0.50).darkened(rng.randf() * 0.2),
					Vector3(x - 0.24 + float(i) * 0.36, y + box_size.y * 0.5 + 0.02, 0.0), 0.92)
	_panel(root, Vector3(0.06, 2.2, 0.7), METAL, Vector3(width * 0.5 - 0.42, 1.1, 0.0), 0.7, 0.4)
	return root


static func _boxes(at: Vector3) -> Node3D:
	var root := _node("Boxes", at)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	var y := 0.0
	for i: int in 5:
		var size := Vector3(0.44 + rng.randf() * 0.2, 0.3 + rng.randf() * 0.14, 0.4 + rng.randf() * 0.2)
		_panel(root, size, Color(0.74, 0.66, 0.52).darkened(rng.randf() * 0.15),
			Vector3(rng.randfn(0.0, 0.08), y + size.y * 0.5, rng.randfn(0.0, 0.08)), 0.92)
		y += size.y
	return root


static func _crates(at: Vector3) -> Node3D:
	var root := _node("Crates", at)
	for i: int in 3:
		_panel(root, Vector3(0.7, 0.5, 0.5), WOOD_LIGHT,
			Vector3(float(i % 2) * 0.1, 0.25 + float(i) * 0.5, 0.0), 0.92)
	return root


# --- Гараж ------------------------------------------------------------------


static func _workbench(at: Vector3, room: Vector3) -> Node3D:
	var root := _node("Workbench", at)
	var length := minf(room.z - 1.4, 4.0)
	_panel(root, Vector3(0.72, 0.08, length), Color(0.30, 0.30, 0.32), Vector3(0.0, 0.9, 0.0), 0.7, 0.3)
	for z: float in [-length * 0.4, 0.0, length * 0.4]:
		_panel(root, Vector3(0.62, 0.86, 0.06), METAL, Vector3(0.0, 0.45, z), 0.75, 0.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3120
	for i: int in 6:
		_panel(root, Vector3(0.1 + rng.randf() * 0.14, 0.1, 0.1 + rng.randf() * 0.2),
			METAL.lightened(rng.randf() * 0.25),
			Vector3(rng.randf_range(-0.2, 0.2), 0.99, rng.randf_range(-length * 0.45, length * 0.45)),
			0.6, 0.55)
	return root


static func _tool_board(at: Vector3, room: Vector3) -> Node3D:
	var root := _node("ToolBoard", at)
	var width := minf(room.x - 1.6, 2.6)
	_panel(root, Vector3(width, 1.3, 0.05), Color(0.30, 0.24, 0.20), Vector3(0.0, 0.9, 0.0), 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6413
	for i: int in 9:
		var x := (float(i) / 8.0 - 0.5) * (width - 0.3)
		_panel(root, Vector3(0.07, 0.24 + rng.randf() * 0.3, 0.04), METAL,
			Vector3(x, 1.0 - rng.randf() * 0.25, -0.05), 0.5, 0.7)
	return root


static func _tyre_stack(at: Vector3) -> Node3D:
	var root := _node("Tyres", at)
	for i: int in 4:
		var tyre := MeshFactory.wheel(0.48, 0.30)
		tyre.position = Vector3(0.0, 0.16 + float(i) * 0.31, 0.0)
		tyre.rotation = Vector3(0.0, 0.0, PI * 0.5)
		root.add_child(tyre)
	return root


## Подъёмник: два столба и лапы. Именно он отличает гараж от сарая.
static func _lift(at: Vector3, room: Vector3) -> Node3D:
	var root := _node("Lift", at)
	var span := minf(room.x - 2.4, 2.8)
	for side: float in [-1.0, 1.0]:
		_panel(root, Vector3(0.28, 2.6, 0.28), Color(0.72, 0.54, 0.12),
			Vector3(side * span * 0.5, 1.3, 0.0), 0.65, 0.4)
		_panel(root, Vector3(0.5, 0.1, 0.5), DARK, Vector3(side * span * 0.5, 0.05, 0.0), 0.8, 0.3)
		for z: float in [-1.1, 1.1]:
			_panel(root, Vector3(0.9, 0.12, 0.18), Color(0.72, 0.54, 0.12),
				Vector3(side * (span * 0.5 - 0.5), 0.42, z), 0.65, 0.4)
	return root


# --- Оазис и улица ----------------------------------------------------------


static func _fountain(at: Vector3) -> Node3D:
	var root := _node("Fountain", at)
	var segments := 14
	for i: int in segments:
		var angle := float(i) / float(segments) * TAU
		_panel(root, Vector3(0.36, 0.44, 1.5 * TAU / float(segments) * 1.2),
			Color(0.86, 0.84, 0.80), Vector3(cos(angle) * 1.5, 0.22, sin(angle) * 1.5), 0.55)
		var panel := root.get_child(root.get_child_count() - 1) as Node3D
		panel.rotation.y = -angle
	# Вода.
	var water := MeshFactory.glass(Vector3(2.8, 0.06, 2.8), Color(0.35, 0.58, 0.62, 0.55))
	water.position = Vector3(0.0, 0.30, 0.0)
	root.add_child(water)
	_panel(root, Vector3(0.3, 0.9, 0.3), Color(0.84, 0.82, 0.78), Vector3(0.0, 0.5, 0.0), 0.5)
	return root


## Пальма. Ствол кольцами, крона из склонённых листьев — силуэт узнаётся с
## любого расстояния, а стоит двадцать панелей.
static func palm(at: Vector3, scale_value: float = 1.0, seed_value: int = 11) -> Node3D:
	var root := _node("Palm", at)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var height := (4.6 + rng.randf() * 2.4) * scale_value
	var lean := Vector2(rng.randfn(0.0, 0.10), rng.randfn(0.0, 0.10))
	var rings := 11
	for i: int in rings:
		var t := float(i) / float(rings - 1)
		var y := t * height
		var bend := Vector2(lean.x, lean.y) * (t * t) * height * 0.5
		var ring := _panel(root, Vector3(0.30 - t * 0.09, height / float(rings) * 1.1, 0.30 - t * 0.09),
			Color(0.42, 0.34, 0.24).lightened(t * 0.12), Vector3(bend.x, y, bend.y), 0.95)
		ring.rotation = Vector3(lean.y * t, 0.0, -lean.x * t)
	var crown := Vector3(lean.x * height * 0.5, height, lean.y * height * 0.5)
	for i: int in 9:
		var angle := float(i) / 9.0 * TAU + rng.randf() * 0.2
		var frond := _node("Frond", crown)
		root.add_child(frond)
		var length := (1.9 + rng.randf() * 0.9) * scale_value
		for k: int in 5:
			var t := float(k) / 4.0
			# Лист провисает к концу: прямой торчащий лист выглядит как перо.
			var droop := -t * t * length * 0.55
			_panel(frond, Vector3(0.30 - t * 0.16, 0.05, length * 0.24),
				Color(0.22, 0.40, 0.18).lightened(t * 0.16),
				Vector3(cos(angle) * t * length, droop, sin(angle) * t * length), 0.92)
	return root


static func _tv_wall(at: Vector3, room: Vector3) -> Node3D:
	var root := _node("TvWall", at)
	var width := minf(room.x - 2.0, 3.2)
	_panel(root, Vector3(width, width * 0.56, 0.08), Color(0.08, 0.08, 0.09), Vector3(0.0, 1.2, 0.0), 0.3, 0.2)
	_panel(root, Vector3(width * 0.96, width * 0.53, 0.02), Color(0.14, 0.18, 0.22), Vector3(0.0, 1.2, -0.05), 0.1, 0.0)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0.0, 1.2, -0.4)
	glow.light_color = Color(0.55, 0.70, 1.0)
	glow.light_energy = 0.9
	glow.omni_range = 4.0
	glow.shadow_enabled = false
	root.add_child(glow)
	return root


static func _chandelier(at: Vector3) -> Node3D:
	var root := _node("Chandelier", at)
	_panel(root, Vector3(0.04, 0.5, 0.04), Color(0.72, 0.60, 0.26), Vector3(0.0, 0.25, 0.0), 0.35, 0.8)
	for i: int in 8:
		var angle := float(i) / 8.0 * TAU
		_panel(root, Vector3(0.09, 0.18, 0.09), Color(0.95, 0.88, 0.62),
			Vector3(cos(angle) * 0.42, -0.1, sin(angle) * 0.42), 0.25, 0.1)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, -0.1, 0.0)
	lamp.light_color = Color(1.0, 0.88, 0.66)
	lamp.light_energy = 2.2
	lamp.omni_range = 9.0
	lamp.shadow_enabled = false
	root.add_child(lamp)
	return root


static func _tea_set(at: Vector3) -> Node3D:
	var root := _node("TeaSet", at)
	_panel(root, Vector3(0.20, 0.24, 0.20), Color(0.72, 0.62, 0.22), Vector3(0.0, 0.12, 0.0), 0.3, 0.7)
	_panel(root, Vector3(0.05, 0.10, 0.05), Color(0.72, 0.62, 0.22), Vector3(0.14, 0.18, 0.0), 0.3, 0.7)
	for i: int in 3:
		var angle := float(i) / 3.0 * TAU
		_panel(root, Vector3(0.08, 0.07, 0.08), Color(0.90, 0.86, 0.78),
			Vector3(cos(angle) * 0.28, 0.035, sin(angle) * 0.28), 0.4)
	return root
