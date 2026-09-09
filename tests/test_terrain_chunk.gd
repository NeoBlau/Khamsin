extends TestCase
## Геометрия и коллизия чанка.
##
## Главная проверка здесь — что земля, по которой едет машина, совпадает с
## землёй, которую видит игрок. Меш и HeightMapShape3D строятся из одной
## функции, но масштабируются по-разному, и именно на этом стыке ошибка была бы
## незаметной до первого проваливающегося сквозь дюну грузовика.

const SEED := 20260907
const SIZE := 256.0
const CELL := 2.0

var field: TerrainField
var world: Node3D


func before_each() -> void:
	field = TerrainField.new(SEED)
	field.apply_config()


func after_each() -> void:
	if world != null and is_instance_valid(world):
		world.queue_free()
	world = null


func test_surface_arrays_have_expected_shape() -> void:
	var data := TerrainChunk.build_data(field, Vector2.ZERO, SIZE, 16, CELL, false, false, SEED)
	var arrays: Array = data["surface"]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var grid := 17 * 17
	check_equal(vertices.size(), grid + 4 * 17, "вершины сетки плюс четыре полосы юбки")
	check_equal(indices.size(), 16 * 16 * 6 + 4 * 16 * 6, "треугольники сетки плюс юбка")
	check_equal(arrays[Mesh.ARRAY_COLOR].size(), vertices.size(), "цвет должен быть у каждой вершины")


func test_mesh_matches_the_height_field() -> void:
	var origin := Vector2(512.0, -768.0)
	var divisions := 32
	var data := TerrainChunk.build_data(field, origin, SIZE, divisions, CELL, false, false, SEED)
	var vertices: PackedVector3Array = data["surface"][Mesh.ARRAY_VERTEX]
	var step := SIZE / float(divisions)
	var line := divisions + 1
	for j: int in range(0, line, 7):
		for i: int in range(0, line, 7):
			var v := vertices[j * line + i]
			var expected := field.height(origin.x + float(i) * step, origin.y + float(j) * step)
			if not check_near(v.y, expected, 0.001, "вершина (%d, %d) должна лежать на рельефе" % [i, j]):
				return


func test_collision_heightmap_matches_the_height_field() -> void:
	var origin := Vector2(-1024.0, 256.0)
	var data := TerrainChunk.build_data(field, origin, SIZE, 32, CELL, true, false, SEED)
	var width: int = data["collision_width"]
	var heights: PackedFloat32Array = data["heights"]
	check_equal(width, int(SIZE / CELL) + 1, "ширина сетки коллизии")
	check_equal(heights.size(), width * width, "коллизия должна быть квадратной")
	for j: int in range(0, width, 13):
		for i: int in range(0, width, 13):
			# Значения хранятся делёнными на шаг: узел коллизии масштабируется
			# равномерно и домножает их обратно.
			var stored := heights[j * width + i] * CELL
			var expected := field.height(origin.x + float(i) * CELL, origin.y + float(j) * CELL)
			if not check_near(stored, expected, 0.001, "высота коллизии (%d, %d)" % [i, j]):
				return


func test_skirt_hangs_below_its_own_edge() -> void:
	# Юбка должна висеть под своим краем, а не под самой низкой точкой чанка:
	# на перепаде в двести метров рельефа второе невозможно и не нужно.
	var data := TerrainChunk.build_data(field, Vector2.ZERO, SIZE, 8, CELL, false, false, SEED)
	var vertices: PackedVector3Array = data["surface"][Mesh.ARRAY_VERTEX]
	var line := 9
	var grid := line * line
	check_equal(vertices.size() - grid, 4 * line, "юбка — это четыре полосы по краю")

	var by_column: Dictionary[Vector2i, float] = {}
	for i: int in grid:
		var v := vertices[i]
		by_column[Vector2i(roundi(v.x), roundi(v.z))] = v.y
	for i: int in range(grid, vertices.size()):
		var v := vertices[i]
		var key := Vector2i(roundi(v.x), roundi(v.z))
		if not check(by_column.has(key), "вершина юбки должна стоять под краем сетки"):
			return
		if not check_near(
			by_column[key] - v.y, TerrainChunk.skirt_depth(SIZE / 8.0), 0.001, "глубина юбки"
		):
			return

	# И она обязана перекрывать разницу высот между соседними уровнями детализации.
	var fine: PackedVector3Array = TerrainChunk.build_data(
		field, Vector2.ZERO, SIZE, 128, CELL, false, false, SEED
	)["surface"][Mesh.ARRAY_VERTEX]
	var coarse: PackedVector3Array = TerrainChunk.build_data(
		field, Vector2.ZERO, SIZE, 8, CELL, false, false, SEED
	)["surface"][Mesh.ARRAY_VERTEX]
	var worst := 0.0
	for i: int in 9:
		# Общие вершины: каждая шестнадцатая у мелкой сетки совпадает с грубой.
		worst = maxf(worst, absf(fine[i * 16].y - coarse[i].y))
	# Юбка грубого чанка должна перекрывать его собственную ошибку огрубления:
	# именно она определяет, насколько его поверхность разойдётся с соседней.
	var depth := TerrainChunk.skirt_depth(SIZE / 8.0)
	check(depth > worst, "юбка (%.0f м) должна быть глубже расхождения LOD (%.1f м)" % [depth, worst])
	# И наоборот: у ближнего чанка юбка должна быть короткой, иначе на склоне
	# из-под него торчит стенка.
	check(
		TerrainChunk.skirt_depth(SIZE / 128.0) < 5.0,
		"у самой мелкой сетки юбка должна быть незаметной"
	)


func test_scatter_avoids_the_dunes() -> void:
	# Камни лежат на щебне и на скалах. В дюнном поле их не видно — засыпаны.
	var rocky := 0
	var sandy := 0
	for coordinate: Vector2i in [Vector2i(0, 0), Vector2i(4, -3), Vector2i(-7, 6), Vector2i(9, 9)]:
		var origin := Vector2(float(coordinate.x) * SIZE, float(coordinate.y) * SIZE)
		var data := TerrainChunk.build_data(field, origin, SIZE, 16, CELL, false, true, SEED)
		var scatter: PackedVector3Array = data["scatter"]
		for i: int in range(0, scatter.size(), 2):
			var place := scatter[i]
			var id := field.surface_id_at(origin.x + place.x, origin.y + place.z)
			if id == &"sand_soft" or id == &"sand_firm":
				sandy += 1
			else:
				rocky += 1
	check_greater(float(rocky + sandy), 20.0, "камни должны вообще появляться")
	check(
		float(sandy) / float(maxi(rocky + sandy, 1)) < 0.25,
		"в песке камней быть почти не должно: %d из %d" % [sandy, rocky + sandy]
	)


func test_truck_rests_on_generated_terrain() -> void:
	# Самая важная проверка модуля: масштабированный HeightMapShape3D обязан
	# оказаться ровно там, где его нарисовали. Ставим машину над известной
	# точкой и смотрим, на какой высоте она встала.
	world = Node3D.new()
	host.add_child(world)

	var origin := Vector2(0.0, 0.0)
	var data := TerrainChunk.build_data(field, origin, SIZE, 128, CELL, true, false, SEED)
	var chunk := TerrainChunk.new()
	chunk.setup(Vector2i.ZERO, SIZE, null)
	world.add_child(chunk)
	chunk.apply_data(data, 0, CELL, null)
	check(chunk.has_collision, "у чанка должна появиться коллизия")

	var spot := Vector2(SIZE * 0.5, SIZE * 0.5)
	var ground := field.height(spot.x, spot.y)

	var truck := VehicleBody.new()
	truck.config_id = &"tabuk_6t"
	truck.player_controlled = false
	truck.surface_provider = func(point: Vector3) -> Surface: return field.surface_at(point.x, point.z)
	world.add_child(truck)
	truck.global_position = Vector3(spot.x, ground + 4.0, spot.y)
	await simulate(3.5)

	var load_per_wheel := truck.mass * Config.gravity / float(truck.wheels.size())
	var compression := load_per_wheel / truck.config.spring_rate
	var expected := ground + truck.wheels[0].max_ray_length() - compression
	check_near(
		truck.global_position.y, expected, 1.2,
		"машина должна стоять на сгенерированной земле, а не над ней и не в ней"
	)
	check(truck.global_position.y > ground, "машина не должна проваливаться сквозь ландшафт")
	var grounded := 0
	for wheel: VehicleWheel in truck.wheels:
		if wheel.grounded:
			grounded += 1
	check_greater(float(grounded), 3.5, "все четыре колеса должны нащупать землю")


func test_vertex_colours_survive_the_array_mesh() -> void:
	# Шейдер ландшафта красит песок и камень по цвету вершины. Если ArrayMesh
	# не сохранит этот массив, покрытие в кадре развалится в однотонную кашу, а
	# в коде всё будет выглядеть правильно — поэтому проверяем на выходе меша.
	var origin := Vector2(1024.0, -1280.0)
	var data := TerrainChunk.build_data(field, origin, SIZE, 32, CELL, false, false, SEED)
	var source: PackedColorArray = data["surface"][Mesh.ARRAY_COLOR]
	check_greater(float(source.size()), 100.0, "цвета должны быть у всех вершин")

	var distinct: Dictionary[Color, bool] = {}
	for colour: Color in source:
		distinct[colour] = true
	check_greater(float(distinct.size()), 1.0, "на чанке должно встречаться больше одного покрытия")

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["surface"])
	check(
		(mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0,
		"меш обязан объявить, что у него есть цвет вершин"
	)
	var restored: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check_equal(restored.size(), source.size(), "число цветов после сборки меша")
	for i: int in mini(restored.size(), 64):
		if not check(
			_colour_close(restored[i], source[i], 0.02),
			"цвет вершины %d изменился: было %s, стало %s" % [i, source[i], restored[i]]
		):
			return


static func _colour_close(a: Color, b: Color, tolerance: float) -> bool:
	return (
		absf(a.r - b.r) <= tolerance
		and absf(a.g - b.g) <= tolerance
		and absf(a.b - b.b) <= tolerance
	)


func test_triangle_winding_matches_the_engine() -> void:
	# Порядок обхода вершин решает, какая сторона треугольника лицевая. Ошибка
	# здесь не даёт ни предупреждения, ни красного экрана: поверхность просто
	# исчезает, и остаются торчать юбки, которые легко принять за рельеф.
	#
	# Соглашение не угадываем, а спрашиваем у движка: берём PlaneMesh, который
	# заведомо смотрит вверх, и меряем его первый треугольник тем же способом.
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	var reference := _first_triangle_normal(plane.get_mesh_arrays())
	# У Godot лицевая грань обходится по часовой стрелке, поэтому «нормаль» по
	# правилу правой руки у плоскости, смотрящей вверх, направлена вниз.
	check(
		absf(reference.y) > 0.9,
		"эталонная плоскость должна быть горизонтальной, получили %s" % reference
	)

	var data := TerrainChunk.build_data(field, Vector2.ZERO, SIZE, 8, CELL, false, false, SEED)
	var ours := _first_triangle_normal(data["surface"])
	check_greater(
		ours.dot(reference), 0.0,
		"обход вершин ландшафта должен совпадать с движком: эталон %s, у нас %s"
			% [reference, ours]
	)

	# И заодно: у всех треугольников сетки нормаль по правилу правой руки
	# смотрит в ту же сторону, что и у эталона.
	var vertices: PackedVector3Array = data["surface"][Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = data["surface"][Mesh.ARRAY_INDEX]
	var grid_triangles := 8 * 8 * 2
	for t: int in grid_triangles:
		var normal := _triangle_normal(
			vertices[indices[t * 3]], vertices[indices[t * 3 + 1]], vertices[indices[t * 3 + 2]]
		)
		if not check(
			normal.dot(reference) > 0.0, "треугольник %d вывернут наизнанку" % t
		):
			return


func _first_triangle_normal(arrays: Array) -> Vector3:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	return _triangle_normal(vertices[indices[0]], vertices[indices[1]], vertices[indices[2]])


func _triangle_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (b - a).cross(c - a).normalized()


func test_changing_lod_keeps_the_collision_under_the_wheels() -> void:
	# Уровень детализации меняется прямо под едущей машиной. Если при этом
	# пересоздавать форму коллизии, физика на кадр теряет опору: на ровном
	# месте незаметно, на склоне дюны машина проваливается и переворачивается.
	world = Node3D.new()
	host.add_child(world)

	var chunk := TerrainChunk.new()
	chunk.setup(Vector2i.ZERO, SIZE, null)
	world.add_child(chunk)

	var detailed := TerrainChunk.build_data(field, Vector2.ZERO, SIZE, 128, CELL, true, false, SEED)
	chunk.apply_data(detailed, 0, CELL, null, true)
	check(chunk.has_collision, "сначала коллизия должна появиться")
	var shape := chunk.get_node("Ground/CollisionShape3D") as CollisionShape3D
	var first := shape.shape

	# Тот же чанк на грубой сетке и без пересчёта коллизии.
	var coarse := TerrainChunk.build_data(field, Vector2.ZERO, SIZE, 16, CELL, false, false, SEED)
	chunk.apply_data(coarse, 3, CELL, null, true)
	check(chunk.has_collision, "после смены детализации коллизия должна остаться")
	check(shape.shape == first, "и остаться той же самой формой, а не пересозданной")
	check_equal(chunk.lod, 3, "визуальный уровень при этом меняется")

	# А вот когда чанк уезжает из ближнего кольца, коллизию надо убрать.
	chunk.apply_data(coarse, 4, CELL, null, false)
	check(not chunk.has_collision, "вдали от игрока коллизия должна сниматься")
