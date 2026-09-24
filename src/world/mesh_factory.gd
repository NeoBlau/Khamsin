class_name MeshFactory
extends RefCounted
## Процедурная геометрия. В проекте нет ни одной импортированной модели, и это
## осознанное решение на старте: механика важнее вида, а примитивы не мешают
## менять размеры машины прямо в JSON. Когда появятся настоящие модели, сюда
## подставляются загруженные меши — остальной код об этом не узнает.


## Камень: сфера с загрублённой сеткой и смещёнными вершинами. Один меш на все
## валуны, разнообразие даёт масштаб и поворот в MultiMesh.
static func rock(seed_value: int = 1, radius: float = 0.8) -> ArrayMesh:
	var source := SphereMesh.new()
	source.radius = radius
	source.height = radius * 1.7
	source.radial_segments = 7
	source.rings = 4
	var arrays := source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Смещение в основном радиальное: так валун остаётся звёздчатым
	# относительно центра — каждая грань по-прежнему смотрит наружу, и
	# пересчитанные нормали не выворачиваются на отдельных вершинах.
	# Небольшая касательная добавка ломает правильность силуэта.
	for i: int in vertices.size():
		var v := vertices[i]
		var direction := v.normalized() if v.length_squared() > 0.000001 else Vector3.UP
		var radial := clampf(rng.randfn(0.0, 0.16), -0.34, 0.34)
		var tangential := Vector3(rng.randfn(0.0, 0.05), rng.randfn(0.0, 0.035), rng.randfn(0.0, 0.05))
		tangential -= direction * tangential.dot(direction)
		vertices[i] = v + direction * radial * radius + tangential * radius
	# Камни в пустыне не шары: ветер и песок сдувают их в приплюснутые глыбы.
	for i: int in vertices.size():
		vertices[i] = vertices[i] * Vector3(1.0, 0.72, 0.92)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	# Смещение вершин может сложить отдельный треугольник наизнанку — чаще
	# всего на полюсе, где у вершины всего одна грань. Вывернутый треугольник
	# не просто криво освещён: отсечение задних граней его вовсе не рисует, и
	# в камне остаётся дырка, сквозь которую видно фон. Разворачиваем намотку
	# наружу по всему мешу, он для этого достаточно «звёздчатый».
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	orient_outward(vertices, indices)
	arrays[Mesh.ARRAY_INDEX] = indices
	# Нормали пересчитываем по граням: после смещения старые врут, и камень
	# начинает бликовать как надувной.
	arrays[Mesh.ARRAY_NORMAL] = face_normals(vertices, indices)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Без материала Godot рисует поверхность белой по умолчанию, и валун в
	# пустыне выглядит вырезанным из бумаги. Камень тут сухой, шершавый и
	# чуть темнее песка — иначе он теряется в нём на солнце.
	var material := standard_material(Color(0.34, 0.30, 0.26), 0.96)
	material.albedo_color = material.albedo_color.lerp(Color(0.46, 0.42, 0.36), 0.35)
	mesh.surface_set_material(0, material)
	return mesh


## Разворачивает намотку треугольников наружу. Годится для мешей,
## звёздчатых относительно своего центра: камень, купол, валун. Возвращает
## число исправленных треугольников — по нему пишется тест.
static func orient_outward(vertices: PackedVector3Array, indices: PackedInt32Array) -> int:
	var centre := centroid(vertices)
	var flipped := 0
	for i: int in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		var normal := (c - a).cross(b - a)
		var outward := (a + b + c) / 3.0 - centre
		if normal.dot(outward) < 0.0:
			var swap := indices[i + 1]
			indices[i + 1] = indices[i + 2]
			indices[i + 2] = swap
			flipped += 1
	return flipped


static func centroid(vertices: PackedVector3Array) -> Vector3:
	if vertices.size() == 0:
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for v: Vector3 in vertices:
		sum += v
	return sum / float(vertices.size())


static func face_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i: int in normals.size():
		normals[i] = Vector3.ZERO
	for i: int in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		# Лицевая грань в Godot — по часовой стрелке, поэтому наружная нормаль
		# это (c-a)×(b-a), а не наоборот. С перепутанным знаком камень
		# освещается изнутри: снаружи он выглядит тёмным пятном, сквозь
		# которое будто просвечивает фон.
		var n := (c - a).cross(b - a)
		for k: int in 3:
			normals[indices[i + k]] += n
	# Вершина, у которой все треугольники вырождены (полюс сферы — ровно такой
	# случай), даёт нулевую сумму. Запасным вариантом тут должно быть
	# направление наружу от центра меша, а не слепое «вверх»: иначе на полюсе
	# появляется одна вывернутая нормаль и камень блестит там чёрной точкой.
	var centre := centroid(vertices)
	for i: int in normals.size():
		if normals[i].length_squared() > 0.0:
			normals[i] = normals[i].normalized()
		else:
			var outward := vertices[i] - centre
			normals[i] = outward.normalized() if outward.length_squared() > 0.0 else Vector3.UP
	return normals


static func standard_material(colour: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.metallic = metallic
	return material


## Коробка с заданными размерами и цветом — кирпич, из которого собран грузовик.
static func box(size: Vector3, colour: Color, roughness: float = 0.7, metallic: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = standard_material(colour, roughness, metallic)
	return instance


## Колесо: цилиндр, положенный набок, с тёмным протектором и светлым диском.
static func wheel(radius: float, width: float) -> Node3D:
	var root := Node3D.new()
	var tyre := CylinderMesh.new()
	tyre.top_radius = radius
	tyre.bottom_radius = radius
	tyre.height = width
	tyre.radial_segments = 20
	tyre.rings = 1
	var tyre_instance := MeshInstance3D.new()
	tyre_instance.mesh = tyre
	tyre_instance.material_override = standard_material(Color(0.10, 0.10, 0.11), 0.95)
	# Цилиндр в Godot стоит вдоль Y, колесо должно лежать вдоль X.
	tyre_instance.rotation = Vector3(0.0, 0.0, PI * 0.5)
	root.add_child(tyre_instance)

	var hub := CylinderMesh.new()
	hub.top_radius = radius * 0.45
	hub.bottom_radius = radius * 0.45
	hub.height = width * 1.04
	hub.radial_segments = 12
	var hub_instance := MeshInstance3D.new()
	hub_instance.mesh = hub
	hub_instance.material_override = standard_material(Color(0.42, 0.40, 0.36), 0.55, 0.4)
	hub_instance.rotation = Vector3(0.0, 0.0, PI * 0.5)
	root.add_child(hub_instance)
	return root
