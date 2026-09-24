extends TestCase
## Процедурная геометрия: камни.
##
## Баг, ради которого написан этот файл: нормали граней считались как
## (b-a)×(c-a), а лицевая грань в Godot — по часовой стрелке, так что знак был
## обратный. Камень освещался изнутри. Хуже того, смещение вершин складывало
## отдельные треугольники наизнанку, а такие треугольники отсечение задних
## граней просто не рисует — в камне оставалась дырка. Со стороны это выглядит
## как «камни почему-то прозрачные».


func _outwardness(vertices: PackedVector3Array, normals: PackedVector3Array) -> float:
	var centre := MeshFactory.centroid(vertices)
	var worst := 1.0
	for i: int in vertices.size():
		var outward := vertices[i] - centre
		if outward.length_squared() < 0.000001:
			continue
		worst = minf(worst, normals[i].dot(outward.normalized()))
	return worst


## Эталон здесь — сам движок: нормали, посчитанные нашей функцией на нетронутой
## сфере, обязаны совпасть с нормалями, которые SphereMesh выдаёт сам. Это
## ловит перепутанный знак сразу и не зависит от нашего представления о том,
## какая намотка «правильная».
func test_face_normals_agree_with_godot() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6
	sphere.radial_segments = 12
	sphere.rings = 8
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var reference: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var ours := MeshFactory.face_normals(vertices, arrays[Mesh.ARRAY_INDEX])
	check_equal(ours.size(), reference.size(), "нормалей столько же, сколько вершин")
	var worst := 1.0
	for i: int in vertices.size():
		worst = minf(worst, ours[i].dot(reference[i]))
	check(worst > 0.9, "худшее совпадение с эталоном SphereMesh: %.3f" % worst)


## Вершина, у которой все грани вырождены, даёт нулевую сумму нормалей.
## Запасным вариантом должно быть направление наружу от центра, а не «вверх»:
## на полюсе сферы это ровно один такой случай, и он давал чёрную точку.
func test_degenerate_vertex_falls_back_outward() -> void:
	var vertices := PackedVector3Array([
		Vector3(0.0, 1.0, 0.0),
		Vector3(1.0, -1.0, 0.0),
		Vector3(-1.0, -1.0, 0.0),
		Vector3(0.0, -1.0, 1.0),
	])
	# Треугольник (0,1,1) вырожден: у вершины 0 нулевая сумма.
	var indices := PackedInt32Array([0, 1, 1])
	var normals := MeshFactory.face_normals(vertices, indices)
	var centre := MeshFactory.centroid(vertices)
	var expected := (vertices[0] - centre).normalized()
	check(normals[0].dot(expected) > 0.99, "нормаль вырожденной вершины смотрит наружу")
	check(not normals[0].is_equal_approx(Vector3.ZERO), "нормаль не нулевая")


func test_orient_outward_repairs_a_flipped_triangle() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 6
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	check_equal(MeshFactory.orient_outward(vertices, indices), 0, "у чистой сферы разворачивать нечего")
	# Выворачиваем один треугольник руками. Берём заведомо невырожденный:
	# на полюсе у SphereMesh есть треугольники нулевой площади, их разворот
	# ничего не меняет и проверять на них нечего.
	var centre := MeshFactory.centroid(vertices)
	var target := -1
	for i: int in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		var facing := (c - a).cross(b - a).dot((a + b + c) / 3.0 - centre)
		if facing > 0.01:
			target = i
			break
	if not check(target >= 0, "нашёлся невырожденный треугольник"):
		return
	var swap := indices[target + 1]
	indices[target + 1] = indices[target + 2]
	indices[target + 2] = swap
	check_equal(MeshFactory.orient_outward(vertices, indices), 1, "ровно один треугольник исправлен")
	check_equal(indices[target + 1], swap, "намотка вернулась на место")
	check_equal(MeshFactory.orient_outward(vertices, indices), 0, "после починки исправлять нечего")


## Главная проверка. Гоняется по многим сидам, потому что форму камня задаёт
## сид мира: баг вылезал не на каждом.
func test_rock_has_no_holes_on_any_seed() -> void:
	for seed_value: int in [1, 7, 42, 20260907, 99991, -13]:
		var mesh := MeshFactory.rock(seed_value, 0.8)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var centre := MeshFactory.centroid(vertices)
		var inside_out := 0
		for i: int in range(0, indices.size(), 3):
			var a := vertices[indices[i]]
			var b := vertices[indices[i + 1]]
			var c := vertices[indices[i + 2]]
			var normal := (c - a).cross(b - a)
			if normal.dot((a + b + c) / 3.0 - centre) < 0.0:
				inside_out += 1
		check_equal(inside_out, 0, "сид %d: вывернутых треугольников" % seed_value)


func test_rock_normals_point_outward_on_any_seed() -> void:
	for seed_value: int in [1, 7, 42, 20260907, 99991, -13]:
		var mesh := MeshFactory.rock(seed_value, 0.8)
		var arrays := mesh.surface_get_arrays(0)
		var worst := _outwardness(arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL])
		check(worst > 0.0, "сид %d: худшая нормаль наружу %.3f" % [seed_value, worst])


## Меш без материала движок рисует белым по умолчанию. В пустыне такой валун
## выглядит вырезанным из бумаги, и это уже второй способ получить «прозрачный»
## камень — на этот раз глазами, а не геометрией.
func test_rock_carries_a_material() -> void:
	var mesh := MeshFactory.rock(7, 0.8)
	var material := mesh.surface_get_material(0)
	check(material != null, "у камня есть материал")
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		check(standard.albedo_color.a >= 1.0, "камень непрозрачный")
		check(standard.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "прозрачность выключена")
		check(standard.roughness > 0.7, "камень шершавый, а не полированный")


func test_rock_is_not_a_sphere() -> void:
	var mesh := MeshFactory.rock(7, 0.8)
	var aabb := mesh.get_aabb()
	check(aabb.size.y < aabb.size.x, "валун приплюснут ветром, а не круглый")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var centre := MeshFactory.centroid(vertices)
	var shortest := 1000.0
	var longest := 0.0
	for v: Vector3 in vertices:
		var r := (v - centre).length()
		shortest = minf(shortest, r)
		longest = maxf(longest, r)
	check(longest > shortest * 1.25, "радиус гуляет: %.2f против %.2f" % [longest, shortest])


func test_two_seeds_make_two_different_rocks() -> void:
	var a: PackedVector3Array = MeshFactory.rock(1, 0.8).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = MeshFactory.rock(2, 0.8).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var same := 0
	for i: int in mini(a.size(), b.size()):
		if a[i].is_equal_approx(b[i]):
			same += 1
	check(same < a.size() / 2, "разные сиды дают разные камни")
