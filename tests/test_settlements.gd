extends TestCase
## Посёлки в трёх измерениях.
##
## До этого посёлок был выровненной площадкой и всплывающим меню. Проверяется
## то, что ломается незаметно: состав зданий должен следовать из услуг, а не
## из настроения генератора; раскладка — повторяться на одном сиде; сборка —
## не вставать одним куском в кадр, потому что именно в этот момент в посёлок
## и въезжают.

const SEED := 20260907


func before_each() -> void:
	Catalog.ensure_loaded()
	if not World.is_built_for(SEED):
		Rng.set_world_seed(SEED)
		World.build_now(SEED)


func _released(built: Dictionary) -> void:
	var root: Variant = built.get("root")
	if root is Node and is_instance_valid(root):
		(root as Node).free()


func test_every_settlement_builds() -> void:
	for settlement: Settlement in World.settlements:
		var built := SettlementBuilder.build(settlement)
		var root: Node3D = built["root"]
		check(root.get_child_count() > 3, "%s: посёлок не пустой" % settlement.id)
		check((built["doors"] as Array).size() > 0, "%s: есть хотя бы один вход" % settlement.id)
		_released(built)


## Состав зданий следует из услуг. Мастерская без `repair` и почта без `post`
## — это ровно тот случай, когда карта врёт игроку.
func test_buildings_follow_the_services() -> void:
	for settlement: Settlement in World.settlements:
		var built := SettlementBuilder.build(settlement)
		var kinds: Array[StringName] = []
		for door: Dictionary in built["doors"]:
			kinds.append(door["kind"])
		if settlement.has_service(&"repair"):
			check(kinds.has(&"workshop"), "%s: мастерская есть в услугах и стоит на улице" % settlement.id)
		else:
			check(not kinds.has(&"workshop"), "%s: мастерской нет ни там, ни там" % settlement.id)
		if settlement.has_service(&"post"):
			check(kinds.has(&"post"), "%s: почта построена" % settlement.id)
		if settlement.has_service(&"bunk"):
			check(kinds.has(&"guesthouse"), "%s: ночлежка построена" % settlement.id)
		_released(built)


func test_the_mansion_is_only_at_the_oasis() -> void:
	var found: Array[StringName] = []
	for settlement: Settlement in World.settlements:
		var built := SettlementBuilder.build(settlement)
		for door: Dictionary in built["doors"]:
			if door["kind"] == &"mansion":
				found.append(settlement.id)
		_released(built)
	check_equal(found.size(), 1, "особняк на карте ровно один: %s" % [found])
	if found.size() == 1:
		check_equal(found[0], &"wilsacom_oasis", "и он у Дяди Вали")


func test_the_post_office_is_only_at_dubailux() -> void:
	var found: Array[StringName] = []
	for settlement: Settlement in World.settlements:
		var built := SettlementBuilder.build(settlement)
		for door: Dictionary in built["doors"]:
			if door["kind"] == &"post":
				found.append(settlement.id)
		_released(built)
	check_equal(found.size(), 1, "почтовый пункт один: %s" % [found])
	if found.size() == 1:
		check_equal(found[0], &"dubailux", "и это DubaiLux")


func test_layout_repeats_on_the_same_seed() -> void:
	var settlement := World.settlement(&"mahatta")
	var first := SettlementBuilder.build(settlement)
	var second := SettlementBuilder.build(settlement)
	var a: Array = first["doors"]
	var b: Array = second["doors"]
	check_equal(a.size(), b.size(), "входов столько же")
	var same := 0
	for i: int in mini(a.size(), b.size()):
		if (a[i]["at"] as Vector3).is_equal_approx(b[i]["at"] as Vector3) \
			and a[i]["kind"] == b[i]["kind"]:
			same += 1
	check_equal(same, a.size(), "и стоят они там же")
	_released(first)
	_released(second)


## Ни одной вывернутой грани во всём посёлке: такая грань не рисуется вовсе,
## и в стене остаётся дыра на песок.
func test_no_panel_is_inside_out() -> void:
	var built := SettlementBuilder.build(World.settlement(&"wilsacom_oasis"))
	var broken := 0
	var checked := 0
	for node: Node in _all(built["root"]):
		if not (node is MeshInstance3D):
			continue
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if not (mesh is ArrayMesh):
			continue
		checked += 1
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var centre := MeshFactory.centroid(vertices)
		for i: int in range(0, indices.size(), 3):
			var p := vertices[indices[i]]
			var q := vertices[indices[i + 1]]
			var r := vertices[indices[i + 2]]
			if (r - p).cross(q - p).dot((p + q + r) / 3.0 - centre) < -0.000001:
				broken += 1
	check(checked > 200, "панелей проверено: %d" % checked)
	check_equal(broken, 0, "вывернутых граней")
	_released(built)


## Сборка по шагам обязана давать ровно то же, что сборка целиком: иначе
## посёлок в игре и посёлок в тестах — разные посёлки.
func test_stepwise_build_matches_the_whole() -> void:
	var settlement := World.settlement(&"bir_saqr")
	var whole := SettlementBuilder.build(settlement)
	var whole_nodes := _all(whole["root"]).size()
	_released(whole)

	var plan := SettlementBuilder.plan(settlement)
	check((plan["steps"] as Array).size() > 3, "шагов несколько, а не один")
	for step: Callable in plan["steps"]:
		step.call()
	check_equal(_all(plan["root"]).size(), whole_nodes, "узлов столько же")
	_released(plan)


## Дверной проём должен быть проходим. Стена с коллизией во всю длину
## выглядит правильно и не пускает внутрь — заметить это можно только зайдя.
func test_doorways_are_walkable() -> void:
	var room := BuildingBuilder.Room.new()
	room.size = Vector3(6.0, 3.0, 5.0)
	room.centre = Vector3(0.0, 1.5, 0.0)
	room.doors = [&"south"] as Array[StringName]
	var rooms: Array[BuildingBuilder.Room] = [room]
	var built := BuildingBuilder.build(rooms)
	var root: Node3D = built["root"]
	host.add_child(root)

	var space: PhysicsDirectSpaceState3D = host.get_viewport().world_3d.direct_space_state
	# Луч на уровне пояса снаружи до середины комнаты. Насквозь светить
	# нельзя: он упрётся в противоположную стену, у которой двери нет.
	var through: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(0.0, 1.0, 4.0), Vector3(0.0, 1.0, 0.0)
	))
	check(through.is_empty(), "в дверь можно войти")
	# А рядом с проёмом — стена.
	var into_wall: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(2.2, 1.0, 4.0), Vector3(2.2, 1.0, 0.0)
	))
	check(not into_wall.is_empty(), "а сквозь стену рядом — нельзя")
	# И над головой у входа перемычка, а не открытое небо.
	var lintel: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(0.0, 2.7, 4.0), Vector3(0.0, 2.7, 0.0)
	))
	check(not lintel.is_empty(), "над дверью перемычка")
	root.queue_free()


func _all(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in node.get_children():
		out.append(child)
		out.append_array(_all(child))
	return out
