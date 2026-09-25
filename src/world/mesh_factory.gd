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
	# Смещение в основном радиальное: так валун остаётся звёздчатым
	# относительно центра — каждая грань по-прежнему смотрит наружу, и
	# пересчитанные нормали не выворачиваются на отдельных вершинах.
	# Небольшая касательная добавка ломает правильность силуэта.
	#
	# Смещение берётся от координат вершины, а не от её номера, и это не
	# придирка. У сферы Godot шов по долготе и оба полюса — это несколько
	# вершин в одной и той же точке: они различаются только развёрткой. Сдвиг
	# по номеру даёт им разные смещения, они разъезжаются, и в камне
	# открывается щель с ровными краями, сквозь которую видно фон. Снаружи это
	# выглядит как дырка в камне — тот самый «прозрачный камень», который не
	# ловился ни проверкой намотки, ни проверкой нормалей: с геометрией всё в
	# порядке, её просто стало меньше.
	for i: int in vertices.size():
		var v := vertices[i]
		var direction := v.normalized() if v.length_squared() > 0.000001 else Vector3.UP
		var radial := clampf(_position_noise(v, seed_value, 1) * 0.16, -0.34, 0.34)
		var tangential := Vector3(
			_position_noise(v, seed_value, 2) * 0.05,
			_position_noise(v, seed_value, 3) * 0.035,
			_position_noise(v, seed_value, 4) * 0.05
		)
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


## Детерминированный шум от точки, примерно нормальный, в пределах ±3.
##
## Ключевое свойство — не качество распределения, а то, что две вершины в
## одной и той же координате получают одно и то же число. Шов сферы и полюса
## как раз такие: вершины разные, точка одна. Считать от номера вершины нельзя
## (см. rock()), от координат — можно и нужно.
static func _position_noise(point: Vector3, salt: int, channel: int) -> float:
	# Квантование до десятой доли миллиметра: совпадающие вершины у сферы
	# совпадают побитово, но полагаться на это в геометрии не стоит.
	var h := _mix(int(round(point.x * 10000.0)), int(round(point.y * 10000.0)))
	h = _mix(h, int(round(point.z * 10000.0)))
	h = _mix(h, salt)
	h = _mix(h, channel)
	# Сумма трёх равномерных даёт колокол — этого для камня достаточно, а
	# считается втрое дешевле любой честной нормальной величины.
	var total := 0.0
	for i: int in 3:
		h = _mix(h, i + 1)
		total += float(h & 0xFFFFFF) / 16777216.0 * 2.0 - 1.0
	return total


static func _mix(a: int, b: int) -> int:
	# splitmix64 в одну итерацию: дёшево и перемешивает достаточно, чтобы
	# соседние вершины не получали похожие смещения.
	var h := a * 2 + 1
	h = (h ^ b) * -7046029254386353131
	h = h ^ (h >> 29)
	h = h * -4658895280553007687
	return h ^ (h >> 32)


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


## Коробка со снятой фаской. Ребро перестаёт быть математически острым и
## начинает ловить блик — из-за этого силуэт читается объёмным там, где
## обычный BoxMesh выглядит плоской наклейкой. Стоит это восьми треугольников
## на угол и ничего больше.
##
## Намотка не выводится руками: треугольники складываются в любом порядке, а
## потом разворачиваются наружу общей функцией. Коробка выпуклая, так что для
## неё это безошибочно.
static func bevelled_box_mesh(size: Vector3, bevel: float) -> ArrayMesh:
	var half := size * 0.5
	var b := clampf(bevel, 0.0, minf(minf(half.x, half.y), half.z) * 0.9)
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	var add_quad := func(a: Vector3, b2: Vector3, c: Vector3, d: Vector3) -> void:
		var base := vertices.size()
		vertices.append(a)
		vertices.append(b2)
		vertices.append(c)
		vertices.append(d)
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	var add_tri := func(a: Vector3, b2: Vector3, c: Vector3) -> void:
		var base := vertices.size()
		vertices.append(a)
		vertices.append(b2)
		vertices.append(c)
		indices.append_array([base, base + 1, base + 2])

	var inner := Vector3(half.x - b, half.y - b, half.z - b)
	# Нулевая фаска: рёберные полосы и уголки выродились бы в тридцать два
	# треугольника нулевой площади. Рисовать их незачем.
	var flat := b < 0.0005

	# Шесть основных граней, утопленных на фаску.
	for axis: int in 3:
		for side: int in 2:
			var sign_value := 1.0 if side == 0 else -1.0
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var extent := half if flat else inner
			var corners: Array[Vector3] = []
			for quadrant: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]:
				var point := Vector3.ZERO
				point[axis] = half[axis] * sign_value
				point[u] = extent[u] * quadrant.x
				point[v] = extent[v] * quadrant.y
				corners.append(point)
			add_quad.call(corners[0], corners[1], corners[2], corners[3])

	# Двенадцать рёберных полос.
	for axis: int in (0 if flat else 3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for su: float in [1.0, -1.0]:
			for sv: float in [1.0, -1.0]:
				var a := Vector3.ZERO
				var b2 := Vector3.ZERO
				var c := Vector3.ZERO
				var d := Vector3.ZERO
				a[axis] = inner[axis]
				a[u] = half[u] * su
				a[v] = inner[v] * sv
				b2[axis] = inner[axis]
				b2[u] = inner[u] * su
				b2[v] = half[v] * sv
				c[axis] = -inner[axis]
				c[u] = inner[u] * su
				c[v] = half[v] * sv
				d[axis] = -inner[axis]
				d[u] = half[u] * su
				d[v] = inner[v] * sv
				add_quad.call(a, b2, c, d)

	# Восемь угловых треугольников.
	for sx: float in ([] if flat else [1.0, -1.0]):
		for sy: float in [1.0, -1.0]:
			for sz: float in [1.0, -1.0]:
				add_tri.call(
					Vector3(half.x * sx, inner.y * sy, inner.z * sz),
					Vector3(inner.x * sx, half.y * sy, inner.z * sz),
					Vector3(inner.x * sx, inner.y * sy, half.z * sz)
				)

	orient_outward(vertices, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_NORMAL] = face_normals(vertices, indices)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Панель кузова: коробка с фаской, готовая к постановке в сцену.
static func panel(size: Vector3, colour: Color, roughness: float = 0.6,
		metallic: float = 0.0, bevel: float = 0.03) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = bevelled_box_mesh(size, bevel)
	instance.material_override = standard_material(colour, roughness, metallic)
	return instance


## Стекло. Отдельной функцией, потому что у него другой набор свойств:
## прозрачность, слабая шероховатость и отключённая тень — стеклянная панель,
## бросающая плотную тень, сразу выдаёт подделку.
static func glass(size: Vector3, tint: Color = Color(0.58, 0.66, 0.70, 0.14)) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = bevelled_box_mesh(size, minf(0.012, size.min_axis_index()))
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.05
	material.metallic = 0.1
	material.metallic_specular = 0.9
	# Стекло не должно затенять то, что за ним: с включённым приёмом тени
	# лобовое стекло кладёт серую плиту на всю дорогу впереди.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Труба: цилиндр с осью вдоль заданного направления. Выхлоп, стойка, поручень.
static func tube(radius: float, length: float, colour: Color, axis: Vector3 = Vector3.UP,
		roughness: float = 0.55, metallic: float = 0.5, segments: int = 10) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = segments
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = standard_material(colour, roughness, metallic)
	if not axis.is_equal_approx(Vector3.UP):
		instance.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	return instance
