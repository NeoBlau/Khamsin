class_name SandTracks
extends MeshInstance3D
## Видимая колея.
##
## Физику следа считает SandField, но увидеть её нельзя: коллизия и меш
## рельефа остаются гладкими, а продавленность живёт в отдельной сетке. Этот
## узел рисует то, что там записано, — ленту вдоль пути каждого колеса.
##
## Почему лента, а не перестройка рельефа. Кусок ландшафта — это несколько
## тысяч вершин, собранных в фоне; трогать его на ходу значит пересобирать и
## меш, и коллизию каждый раз, когда колесо проехало полметра. Лента стоит
## четыре треугольника на сегмент и обновляется за доли миллисекунды.
##
## Лента живёт в мире, а не на машине: след остаётся там, где его оставили.

## Через сколько метров ставится новый сегмент. Реже — колея на поворотах
## ломается углами, чаще — сегментов становится слишком много.
const STEP := 0.55
## Сколько сегментов помнит одно колесо. При шаге в полметра это около
## шестидесяти метров следа на колесо.
const MEMORY := 120
## Насколько лента приподнята над точкой контакта, чтобы не мерцать с
## рельефом. Меньше миллиметра тут мало: рельеф далеко от камеры дрожит.
const LIFT := 0.012

var vehicle: VehicleBody = null

## По дорожке на колесо: [{pos, right, width, depth, age}]
var _lanes: Array[Array] = []
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	mesh = _mesh
	material_override = _make_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Лента длинная и плоская; отсечение по её же ограничивающему объёму
	# выбрасывало бы её целиком, стоит камере отвернуться от центра.
	extra_cull_margin = 64.0
	top_level = true


func attach(target: VehicleBody) -> void:
	vehicle = target
	_lanes.clear()
	for _i: int in target.wheels.size():
		_lanes.append([])


static func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# Цвет и прозрачность приходят из вершин: у каждого сегмента своя степень
	# выцветания, и одним материалом это не выразить.
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.roughness = 1.0
	material.metallic = 0.0
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# Без смещения лента спорит с рельефом за каждый пиксель и рябит.
	material.render_priority = 1
	material.no_depth_test = false
	return material


func _process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	_collect()
	_age(delta)
	_rebuild()


func _collect() -> void:
	for index: int in vehicle.wheels.size():
		var wheel: VehicleWheel = vehicle.wheels[index]
		var lane: Array = _lanes[index]
		if not wheel.grounded or wheel.surface == null:
			continue
		var depth := wheel.sinkage * wheel.surface.softness()
		if depth < 0.008:
			continue
		var point := wheel.contact_point
		if not lane.is_empty():
			var last: Dictionary = lane[lane.size() - 1]
			if (last[&"pos"] as Vector3).distance_to(point) < STEP:
				continue
		# Ось поперёк следа берётся от кузова, а не от колеса: у повёрнутого
		# колеса она смотрит вдоль борозды, и лента складывается вдвое.
		var across := vehicle.global_transform.basis.x
		lane.append({
			&"pos": point + Vector3.UP * LIFT,
			&"right": across,
			&"width": wheel.spec.width * (1.0 + depth * 1.6),
			&"depth": depth,
			&"age": 0.0,
		})
		if lane.size() > MEMORY:
			lane.remove_at(0)


## След стареет вместе с настоящим: SandField засыпает колею ветром, лента
## гаснет с той же скоростью. Если они разойдутся, игрок увидит борозду там,
## где подвеска её уже не чувствует, и наоборот.
func _age(delta: float) -> void:
	var life := lifetime()
	for lane: Array in _lanes:
		var index := 0
		while index < lane.size():
			var segment: Dictionary = lane[index]
			segment[&"age"] = float(segment[&"age"]) + delta
			if float(segment[&"age"]) > life:
				lane.remove_at(index)
				continue
			index += 1


## Сколько живёт видимый след, секунды. Считается из той же скорости засыпания,
## что и в SandField, — одно число, два потребителя.
static func lifetime() -> float:
	return 0.22 / SandField.WIND_FILL


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var life := lifetime()
	for lane: Array in _lanes:
		if lane.size() < 2:
			continue
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for segment: Dictionary in lane:
			var fade := 1.0 - float(segment[&"age"]) / life
			var alpha := clampf(fade * fade * clampf(float(segment[&"depth"]) * 9.0, 0.25, 1.0), 0.0, 1.0)
			var centre: Vector3 = segment[&"pos"]
			var across: Vector3 = (segment[&"right"] as Vector3) * (float(segment[&"width"]) * 0.5)
			# Песок в колее темнее и матовее целины: он спрессован, а снизу
			# ещё и не высох.
			var tint := Color(0.46, 0.39, 0.29, alpha)
			_mesh.surface_set_color(tint)
			_mesh.surface_set_normal(Vector3.UP)
			_mesh.surface_add_vertex(centre - across)
			_mesh.surface_set_color(tint)
			_mesh.surface_set_normal(Vector3.UP)
			_mesh.surface_add_vertex(centre + across)
		_mesh.surface_end()


## Число сегментов во всех дорожках — для тестов и телеметрии.
func segment_count() -> int:
	var total := 0
	for lane: Array in _lanes:
		total += lane.size()
	return total
