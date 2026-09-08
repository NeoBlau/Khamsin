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
	for i: int in vertices.size():
		var v := vertices[i]
		var jitter := Vector3(rng.randfn(0.0, 0.14), rng.randfn(0.0, 0.10), rng.randfn(0.0, 0.14))
		vertices[i] = v + jitter * radius
	arrays[Mesh.ARRAY_VERTEX] = vertices
	# Нормали пересчитываем по граням: после смещения старые врут, и камень
	# начинает бликовать как надувной.
	arrays[Mesh.ARRAY_NORMAL] = _face_normals(vertices, arrays[Mesh.ARRAY_INDEX])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _face_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i: int in normals.size():
		normals[i] = Vector3.ZERO
	for i: int in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		var n := (b - a).cross(c - a)
		for k: int in 3:
			normals[indices[i + k]] += n
	for i: int in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length_squared() > 0.0 else Vector3.UP
	return normals


static func standard_material(colour: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.metallic = metallic
	return material


## Коробка с заданными размерами и цветом — кирпич, из которого собран грузовик.
static func box(size: Vector3, colour: Color, roughness: float = 0.7, metallic: float = 0.1) -> MeshInstance3D:
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
