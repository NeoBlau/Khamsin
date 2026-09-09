class_name TerrainChunk
extends Node3D
## Кусок ландшафта: меш, коллизия и рассыпанные по нему камни.
##
## Геометрия строится в рабочем потоке из чистых функций TerrainField, поэтому
## тяжёлая часть не трогает основной поток. Сюда приезжает уже готовый набор
## массивов, и остаётся только собрать из них ArrayMesh.
##
## Коллизия — HeightMapShape3D: на порядок дешевле треугольного меша и не даёт
## «щелей» между чанками. Шаг сетки у неё жёстко единичный, поэтому узел
## масштабируется равномерно, а высоты заранее делятся на тот же множитель.

## Минимальная глубина юбки по краю чанка, метры. Юбкой закрываются щели между
## соседями с разным уровнем детализации: честно сшивать сетки дороже, а видно
## одинаково. Глубина адаптивная — она должна перекрывать ошибку огрубления
## сетки и не больше, иначе на склоне из-под чанка торчит стенка.
const SKIRT_MIN_DEPTH := 3.0
const SKIRT_STEP_FACTOR := 1.6

var coordinate: Vector2i = Vector2i.ZERO
var lod: int = 0
var has_collision: bool = false

var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _collision: CollisionShape3D
var _scatter: MultiMeshInstance3D


## Считает всё, что можно посчитать без сцены. Вызывается из рабочего потока.
##
## Возвращает словарь: surface — массивы для ArrayMesh, heights — сетка для
## коллизии (или пустая), scatter — трансформы камней.
static func build_data(
	field: TerrainField,
	origin: Vector2,
	size: float,
	divisions: int,
	collision_cell: float,
	want_collision: bool,
	want_scatter: bool,
	world_seed: int
) -> Dictionary:
	var result := {
		"surface": _build_surface(field, origin, size, divisions),
		"heights": PackedFloat32Array(),
		"collision_width": 0,
		"scatter": PackedVector3Array(),
	}
	if want_collision:
		var width := int(round(size / collision_cell)) + 1
		result["heights"] = _build_heights(field, origin, collision_cell, width)
		result["collision_width"] = width
	if want_scatter:
		result["scatter"] = _build_scatter(field, origin, size, world_seed)
	return result


static func _build_surface(
	field: TerrainField, origin: Vector2, size: float, divisions: int
) -> Array:
	var step := size / float(divisions)
	var line := divisions + 1
	# Сетка с рамкой в одну ячейку: нормали считаются по соседям, а на краю
	# чанка соседей не хватает. Дешевле взять их заранее, чем звать height()
	# по четыре раза на вершину.
	var padded := line + 2
	var grid := PackedFloat32Array()
	grid.resize(padded * padded)
	for j: int in padded:
		var z := origin.y + float(j - 1) * step
		for i: int in padded:
			var x := origin.x + float(i - 1) * step
			grid[j * padded + i] = field.height(x, z)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	vertices.resize(line * line)
	normals.resize(line * line)
	uvs.resize(line * line)
	colors.resize(line * line)

	for j: int in line:
		for i: int in line:
			var index := j * line + i
			var gx := i + 1
			var gz := j + 1
			var h: float = grid[gz * padded + gx]
			vertices[index] = Vector3(float(i) * step, h, float(j) * step)
			var left: float = grid[gz * padded + gx - 1]
			var right: float = grid[gz * padded + gx + 1]
			var back: float = grid[(gz - 1) * padded + gx]
			var front: float = grid[(gz + 1) * padded + gx]
			normals[index] = Vector3(left - right, 2.0 * step, back - front).normalized()
			uvs[index] = Vector2(float(i) / float(divisions), float(j) / float(divisions))
			colors[index] = field.surface_weights(origin.x + float(i) * step, origin.y + float(j) * step)

	var indices := PackedInt32Array()
	indices.resize(divisions * divisions * 6)
	var cursor := 0
	for j: int in divisions:
		for i: int in divisions:
			var a := j * line + i
			var b := a + 1
			var c := a + line
			var d := c + 1
			# Порядок обхода лицевой грани в Godot — по часовой стрелке, если
			# смотреть на неё снаружи. Проверяется тестом по эталонному
			# PlaneMesh: обратный порядок здесь не даёт ни ошибки, ни
			# предупреждения, поверхность просто перестаёт рисоваться.
			indices[cursor] = a
			indices[cursor + 1] = b
			indices[cursor + 2] = c
			indices[cursor + 3] = b
			indices[cursor + 4] = d
			indices[cursor + 5] = c
			cursor += 6

	_append_skirt(vertices, normals, uvs, colors, indices, line, divisions, skirt_depth(step))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Юбка по периметру: копия краевых вершин, опущенная вниз. Сосед с более
## грубым LOD проходит чуть ниже или выше, и без юбки между чанками видно небо.
## Глубина юбки для сетки с заданным шагом. Ошибка огрубления растёт вместе с
## шагом, поэтому у дальних чанков юбка длиннее, а у ближних почти незаметна.
static func skirt_depth(step: float) -> float:
	return maxf(SKIRT_MIN_DEPTH, step * SKIRT_STEP_FACTOR)


static func _append_skirt(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	line: int,
	divisions: int,
	depth: float
) -> void:
	var edges: Array[PackedInt32Array] = []
	var top := PackedInt32Array()
	var bottom := PackedInt32Array()
	var left := PackedInt32Array()
	var right := PackedInt32Array()
	for i: int in line:
		top.append(i)
		bottom.append(divisions * line + i)
		left.append(i * line)
		right.append(i * line + divisions)
	edges.append(top)
	edges.append(bottom)
	edges.append(left)
	edges.append(right)

	# Порядок обхода у противоположных краёв зеркальный, иначе половина юбки
	# окажется вывернутой наизнанку и пропадёт при отсечении задних граней.
	var flipped := [false, true, true, false]
	for e: int in edges.size():
		var edge: PackedInt32Array = edges[e]
		var base := vertices.size()
		for index: int in edge:
			vertices.append(vertices[index] - Vector3(0.0, depth, 0.0))
			normals.append(normals[index])
			uvs.append(uvs[index])
			colors.append(colors[index])
		for i: int in range(edge.size() - 1):
			var a := edge[i]
			var b := edge[i + 1]
			var c := base + i
			var d := base + i + 1
			if flipped[e]:
				indices.append_array([a, c, b, b, c, d])
			else:
				indices.append_array([a, b, c, b, d, c])


static func _build_heights(
	field: TerrainField, origin: Vector2, cell: float, width: int
) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(width * width)
	for j: int in width:
		var z := origin.y + float(j) * cell
		for i: int in width:
			# Делим на шаг: узел коллизии масштабируется равномерно, значит
			# высоты домножатся на тот же коэффициент обратно.
			data[j * width + i] = field.height(origin.x + float(i) * cell, z) / cell
	return data


## Камни и кусты. Плотность зависит от покрытия: на хамаде щебень, в дюнах
## почти ничего, потому что там всё засыпано.
static func _build_scatter(
	field: TerrainField, origin: Vector2, size: float, world_seed: int
) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cell := 16.0
	var count := int(size / cell)
	var chunk_hash := int(origin.x) * 73856093 ^ int(origin.y) * 19349663 ^ world_seed
	for j: int in count:
		for i: int in count:
			var salt := chunk_hash + i * 31 + j * 977
			var roll := _hash_unit(salt)
			var x := origin.x + (float(i) + _hash_unit(salt + 1)) * cell
			var z := origin.y + (float(j) + _hash_unit(salt + 2)) * cell
			var id := field.surface_id_at(x, z)
			var density := 0.0
			match id:
				&"gravel": density = 0.32
				&"rock": density = 0.55
				&"sand_firm": density = 0.06
				&"sabkha": density = 0.02
				_: density = 0.0
			if roll > density:
				continue
			var scale := lerpf(0.35, 1.6, _hash_unit(salt + 3))
			# X, Z — положение в системе чанка, Y — высота; масштаб уезжает в
			# длину вектора, поэтому хватает одного PackedVector3Array.
			out.append(Vector3(x - origin.x, field.height(x, z), z - origin.y))
			out.append(Vector3(scale, _hash_unit(salt + 4) * TAU, 0.0))
	return out


static func _hash_unit(value: int) -> float:
	var h := value
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


# --- Сборка узлов ----------------------------------------------------------

func setup(chunk_coordinate: Vector2i, size: float, material: Material) -> void:
	coordinate = chunk_coordinate
	name = "Chunk_%d_%d" % [coordinate.x, coordinate.y]
	position = Vector3(float(coordinate.x) * size, 0.0, float(coordinate.y) * size)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Surface"
	_mesh_instance.material_override = material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh_instance)


func apply_data(data: Dictionary, chunk_lod: int, collision_cell: float, rock_mesh: Mesh) -> void:
	lod = chunk_lod
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["surface"])
	_mesh_instance.mesh = mesh

	var heights: PackedFloat32Array = data["heights"]
	if heights.is_empty():
		_clear_collision()
	else:
		_apply_collision(heights, int(data["collision_width"]), collision_cell)

	_apply_scatter(data["scatter"], rock_mesh)


func _apply_collision(heights: PackedFloat32Array, width: int, cell: float) -> void:
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "Ground"
		var material := PhysicsMaterial.new()
		material.friction = 1.0
		material.bounce = 0.0
		_body.physics_material_override = material
		add_child(_body)
		_collision = CollisionShape3D.new()
		_body.add_child(_collision)

	var shape := HeightMapShape3D.new()
	shape.map_width = width
	shape.map_depth = width
	shape.map_data = heights
	_collision.shape = shape
	# Форма центрирована в своём начале координат и живёт в единичной сетке,
	# поэтому её надо и сдвинуть в центр чанка, и растянуть до нужного шага.
	_collision.scale = Vector3(cell, cell, cell)
	_collision.position = Vector3(float(width - 1) * cell * 0.5, 0.0, float(width - 1) * cell * 0.5)
	has_collision = true


func _clear_collision() -> void:
	if _body != null:
		_body.queue_free()
		_body = null
		_collision = null
	has_collision = false


func _apply_scatter(data: PackedVector3Array, rock_mesh: Mesh) -> void:
	var count := data.size() / 2
	if count == 0 or rock_mesh == null:
		if _scatter != null:
			_scatter.queue_free()
			_scatter = null
		return
	if _scatter == null:
		_scatter = MultiMeshInstance3D.new()
		_scatter.name = "Scatter"
		_scatter.multimesh = MultiMesh.new()
		_scatter.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_scatter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(_scatter)
	_scatter.multimesh.mesh = rock_mesh
	_scatter.multimesh.instance_count = count
	for i: int in count:
		var place := data[i * 2]
		var params := data[i * 2 + 1]
		var basis := Basis(Vector3.UP, params.y).scaled(Vector3.ONE * params.x)
		_scatter.multimesh.set_instance_transform(i, Transform3D(basis, place))
