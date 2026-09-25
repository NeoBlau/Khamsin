class_name EasterEggProps
extends RefCounted
## Геометрия находок.
##
## Каждая — десяток-другой панелей. Смысл не в подробности, а в том, что вещь
## узнаётся с расстояния и не вписывается в пейзаж: шезлонг, телефонная будка
## и холодильник посреди эрга работают именно тем, что они здесь неуместны.

const METAL := Color(0.46, 0.46, 0.44)
const DARK := Color(0.16, 0.16, 0.17)
const RUST := Color(0.48, 0.30, 0.18)
const CLOTH := Color(0.72, 0.28, 0.24)
const PAPER := Color(0.86, 0.83, 0.74)


static func build(kind: StringName, seed_value: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	match kind:
		&"deck_chair":
			return _deck_chair(rng)
		&"phone_booth":
			return _phone_booth()
		&"milestone":
			return _milestone()
		&"dead_minibus":
			return _dead_minibus(rng)
		&"lone_apple":
			return _lone_apple()
		&"stone_circle":
			return _stone_circle(rng)
		&"teapot":
			return _teapot()
		&"scratched_rock":
			return _scratched_rock(rng)
		&"giant_tracks":
			return _giant_tracks(rng)
		&"fridge":
			return _fridge()
		_:
			return null


static func _root(name: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	return node


static func _panel(parent: Node3D, size: Vector3, colour: Color, at: Vector3,
		roughness: float = 0.85, metallic: float = 0.0) -> MeshInstance3D:
	var panel := MeshFactory.panel(size, colour, roughness, metallic, minf(0.02, size[size.min_axis_index()] * 0.4))
	panel.position = at
	parent.add_child(panel)
	return panel


static func _deck_chair(rng: RandomNumberGenerator) -> Node3D:
	var root := _root("DeckChair")
	# Полосатое полотно на раме, чуть откинутое.
	for i: int in 5:
		_panel(root, Vector3(0.62, 0.04, 0.16),
			CLOTH if i % 2 == 0 else PAPER,
			Vector3(0.0, 0.42 + float(i) * 0.09, -float(i) * 0.14), 0.95)
	for x: float in [-0.32, 0.32]:
		_panel(root, Vector3(0.05, 0.05, 1.0), METAL, Vector3(x, 0.30, 0.0), 0.5, 0.6)
		_panel(root, Vector3(0.05, 0.46, 0.05), METAL, Vector3(x, 0.23, 0.42), 0.5, 0.6)
	# Зонт.
	_panel(root, Vector3(0.06, 2.1, 0.06), METAL, Vector3(0.8, 1.05, 0.2), 0.5, 0.5)
	for i: int in 8:
		var angle := float(i) / 8.0 * TAU
		var sector := _panel(root, Vector3(0.95, 0.04, 0.34),
			CLOTH if i % 2 == 0 else PAPER,
			Vector3(0.8 + cos(angle) * 0.5, 1.98 - 0.06, 0.2 + sin(angle) * 0.5), 0.95)
		sector.rotation = Vector3(0.14, -angle, 0.0)
	# Сумка-холодильник и записка.
	_panel(root, Vector3(0.42, 0.30, 0.30), Color(0.32, 0.52, 0.68), Vector3(-0.7, 0.15, 0.3), 0.8)
	_panel(root, Vector3(0.12, 0.002, 0.09), PAPER, Vector3(0.30, 0.52, 0.30), 0.95)
	return root


static func _phone_booth() -> Node3D:
	var root := _root("PhoneBooth")
	for side: int in 4:
		var along_x := side < 2
		var sign_value := 1.0 if side % 2 == 0 else -1.0
		if side == 1:
			continue  # вход
		var wall := MeshFactory.glass(
			Vector3(0.86, 2.0, 0.04) if along_x else Vector3(0.04, 2.0, 0.86),
			Color(0.66, 0.74, 0.76, 0.22)
		)
		wall.position = Vector3(0.0, 1.05, sign_value * 0.43) if along_x \
			else Vector3(sign_value * 0.43, 1.05, 0.0)
		root.add_child(wall)
	for x: float in [-0.44, 0.44]:
		for z: float in [-0.44, 0.44]:
			_panel(root, Vector3(0.08, 2.2, 0.08), Color(0.62, 0.16, 0.14), Vector3(x, 1.1, z), 0.7)
	_panel(root, Vector3(1.0, 0.12, 1.0), Color(0.62, 0.16, 0.14), Vector3(0.0, 2.2, 0.0), 0.7)
	_panel(root, Vector3(0.96, 0.06, 0.96), DARK, Vector3(0.0, 0.03, 0.0), 0.9)
	# Аппарат и трубка.
	_panel(root, Vector3(0.24, 0.34, 0.14), DARK, Vector3(0.0, 1.25, -0.34), 0.6)
	_panel(root, Vector3(0.08, 0.20, 0.07), Color(0.10, 0.10, 0.11), Vector3(-0.17, 1.28, -0.30), 0.5)
	# Провод, уходящий в песок.
	_panel(root, Vector3(0.03, 1.1, 0.03), DARK, Vector3(0.36, 0.55, -0.36), 0.9)
	return root


static func _milestone() -> Node3D:
	var root := _root("Milestone")
	_panel(root, Vector3(0.14, 2.6, 0.14), Color(0.52, 0.48, 0.42), Vector3(0.0, 1.3, 0.0), 0.9)
	var plates := [
		[0.9, Color(0.86, 0.84, 0.78), 0.6],
		[1.3, Color(0.86, 0.84, 0.78), -0.5],
		[1.7, Color(0.82, 0.80, 0.74), 0.4],
		[2.25, Color(0.90, 0.88, 0.80), -0.9],
	]
	for plate: Array in plates:
		var board := _panel(root, Vector3(0.96, 0.20, 0.04),
			plate[1], Vector3(float(plate[2]) * 0.4, float(plate[0]), 0.0), 0.7)
		board.rotation.y = float(plate[2])
		# Полоска вместо надписи: текста в процедурной геометрии нет.
		var ink := _panel(root, Vector3(0.66, 0.05, 0.02), Color(0.22, 0.20, 0.18),
			board.position + Vector3(0.0, 0.0, 0.03), 0.8)
		ink.rotation.y = board.rotation.y
	return root


static func _dead_minibus(rng: RandomNumberGenerator) -> Node3D:
	var root := _root("DeadMinibus")
	# Кузов по стёкла в песке: видно только верхнюю треть.
	_panel(root, Vector3(1.9, 1.0, 5.0), Color(0.78, 0.76, 0.70), Vector3(0.0, 0.42, 0.0), 0.95)
	_panel(root, Vector3(1.86, 0.06, 4.9), Color(0.70, 0.68, 0.62), Vector3(0.0, 0.94, 0.0), 0.95)
	for side: int in 2:
		var s := 1.0 if side == 0 else -1.0
		var glass := MeshFactory.glass(Vector3(0.03, 0.34, 3.4), Color(0.50, 0.56, 0.56, 0.35))
		glass.position = Vector3(s * 0.94, 0.72, 0.2)
		root.add_child(glass)
	_panel(root, Vector3(0.9, 0.5, 0.02), PAPER, Vector3(0.0, 0.70, -2.45), 0.95)
	_panel(root, Vector3(0.6, 0.07, 0.01), Color(0.24, 0.22, 0.20), Vector3(0.0, 0.74, -2.47), 0.9)
	root.rotation.y = rng.randf_range(-0.6, 0.6)
	root.rotation.z = rng.randf_range(-0.12, 0.12)
	return root


static func _lone_apple() -> Node3D:
	var root := _root("LoneApple")
	_panel(root, Vector3(0.42, 0.26, 0.34), Color(0.92, 0.91, 0.88), Vector3(0.0, 0.13, 0.0), 0.35)
	_panel(root, Vector3(0.43, 0.02, 0.06), Color(0.72, 0.70, 0.66), Vector3(0.0, 0.26, 0.0), 0.4)
	_panel(root, Vector3(0.12, 0.13, 0.005), Color(0.30, 0.30, 0.32), Vector3(0.0, 0.16, 0.175), 0.3)
	return root


static func _stone_circle(rng: RandomNumberGenerator) -> Node3D:
	var root := _root("StoneCircle")
	var count := 11
	for i: int in count:
		var angle := float(i) / float(count) * TAU
		var radius := 5.4 + rng.randf_range(-0.3, 0.3)
		var stone := MeshInstance3D.new()
		stone.mesh = MeshFactory.rock(rng.randi(), rng.randf_range(0.5, 0.85))
		stone.position = Vector3(cos(angle) * radius, 0.25, sin(angle) * radius)
		stone.rotation.y = rng.randf() * TAU
		stone.scale = Vector3(1.0, rng.randf_range(1.6, 2.6), 1.0)
		root.add_child(stone)
	# Антенна в центре: прикопанная мачта, которую видно, только если подойти.
	_panel(root, Vector3(0.07, 1.4, 0.07), Color(0.32, 0.31, 0.30), Vector3(0.0, 0.7, 0.0), 0.6, 0.4)
	_panel(root, Vector3(0.5, 0.18, 0.5), Color(0.24, 0.24, 0.25), Vector3(0.0, 0.09, 0.0), 0.8)
	return root


static func _teapot() -> Node3D:
	var root := _root("Teapot")
	var stone := MeshInstance3D.new()
	stone.mesh = MeshFactory.rock(77, 1.1)
	stone.position = Vector3(0.0, 0.35, 0.0)
	stone.scale = Vector3(1.4, 0.7, 1.4)
	root.add_child(stone)
	_panel(root, Vector3(0.22, 0.26, 0.22), Color(0.72, 0.62, 0.22), Vector3(0.0, 0.85, 0.0), 0.3, 0.7)
	_panel(root, Vector3(0.05, 0.11, 0.05), Color(0.72, 0.62, 0.22), Vector3(0.16, 0.92, 0.0), 0.3, 0.7)
	for i: int in 3:
		var angle := float(i) / 3.0 * TAU
		_panel(root, Vector3(0.08, 0.08, 0.08), Color(0.92, 0.88, 0.80),
			Vector3(cos(angle) * 0.36, 0.76, sin(angle) * 0.36), 0.4)
	return root


static func _scratched_rock(rng: RandomNumberGenerator) -> Node3D:
	var root := _root("ScratchedRock")
	var slab := MeshInstance3D.new()
	slab.mesh = MeshFactory.rock(rng.randi(), 1.5)
	slab.scale = Vector3(1.6, 0.42, 1.2)
	slab.position = Vector3(0.0, 0.45, 0.0)
	root.add_child(slab)
	# Царапины: две строки коротких штрихов.
	for row: int in 2:
		for i: int in 7:
			_panel(root, Vector3(0.07, 0.01, 0.03), Color(0.86, 0.84, 0.78),
				Vector3(-0.5 + float(i) * 0.17, 0.72 - float(row) * 0.02, -0.12 + float(row) * 0.26),
				0.9)
	return root


static func _giant_tracks(rng: RandomNumberGenerator) -> Node3D:
	var root := _root("GiantTracks")
	for side: float in [-3.1, 3.1]:
		for i: int in 26:
			var t := float(i) / 25.0
			var plate := _panel(root, Vector3(2.4, 0.06, 1.1), Color(0.60, 0.55, 0.46),
				Vector3(side + rng.randfn(0.0, 0.12), 0.03, -100.0 + t * 200.0), 0.98)
			plate.rotation.y = rng.randfn(0.0, 0.04)
	return root


static func _fridge() -> Node3D:
	var root := _root("Fridge")
	_panel(root, Vector3(0.62, 1.72, 0.62), Color(0.90, 0.89, 0.86), Vector3(0.0, 0.86, 0.0), 0.35)
	_panel(root, Vector3(0.02, 0.04, 0.60), Color(0.62, 0.62, 0.60), Vector3(0.32, 1.12, 0.0), 0.4, 0.6)
	_panel(root, Vector3(0.64, 0.03, 0.64), Color(0.72, 0.72, 0.70), Vector3(0.0, 1.20, 0.0), 0.4)
	# Столб, к которому он подключён, и провод.
	_panel(root, Vector3(0.14, 2.6, 0.14), Color(0.42, 0.34, 0.24), Vector3(1.6, 1.3, 0.2), 0.9)
	_panel(root, Vector3(1.3, 0.03, 0.03), Color(0.18, 0.18, 0.18), Vector3(0.95, 1.55, 0.1), 0.9)
	return root
