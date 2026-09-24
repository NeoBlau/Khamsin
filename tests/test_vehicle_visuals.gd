extends TestCase
## Сборка машины: геометрия кузова и кабины.
##
## Проверяется не красота, а то, что ломается незаметно: панели с вывернутой
## намоткой (дырки в кузове), точка глаз внутри торпедо или за спинкой,
## стекло, бросающее тень, и грязь, ложащаяся на резину.

var config: VehicleConfig


func before_each() -> void:
	Catalog.ensure_loaded()
	config = Catalog.vehicle(&"tabuk_6t")


func _built() -> Dictionary:
	return ChassisBuilder.build(config)


func test_chassis_has_all_the_parts() -> void:
	var built := _built()
	check(built.has("chassis"), "кузов собран")
	check(built.has("cabin"), "кабина собрана")
	check_equal((built["wheels"] as Array).size(), config.wheels.size(), "колёс столько же, сколько в физике")
	check_equal((built["headlights"] as Array).size(), 2, "две фары")
	check_equal((built["tail_lamps"] as Array).size(), 2, "два задних фонаря")
	check((built["paint"] as Array).size() > 5, "есть окрашиваемые панели")
	_release(built)


## Главная геометрическая проверка: ни одной вывернутой грани во всей машине.
## Вывернутая грань не рисуется вовсе — в кузове остаётся дырка, ровно как
## было с камнями.
func test_no_panel_is_inside_out() -> void:
	var built := _built()
	var chassis: Node3D = built["chassis"]
	var checked := 0
	var broken := 0
	for node: Node in _all_children(chassis):
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
			var a := vertices[indices[i]]
			var b := vertices[indices[i + 1]]
			var c := vertices[indices[i + 2]]
			if (c - a).cross(b - a).dot((a + b + c) / 3.0 - centre) < -0.000001:
				broken += 1
	check(checked > 15, "панелей с процедурной геометрией проверено: %d" % checked)
	check_equal(broken, 0, "вывернутых граней")
	_release(built)


func test_glass_does_not_cast_shadow() -> void:
	# Стекло, бросающее плотную тень, выдаёт подделку мгновенно: на дороге
	# перед машиной появляется серая плита.
	var glass := MeshFactory.glass(Vector3(1.0, 0.6, 0.03))
	check_equal(glass.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "тень выключена")
	var material := glass.material_override as StandardMaterial3D
	check(material != null, "материал есть")
	check_equal(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "прозрачность включена")
	check(material.albedo_color.a < 0.35, "стекло прозрачное, а не матовое: альфа %.2f" % material.albedo_color.a)
	glass.free()


func test_paint_list_excludes_glass_and_rubber() -> void:
	# По этому списку потом ходят пыль и верблюжьи плевки. Грязь на стекле
	# изнутри и грязь на резине — два разных способа испортить картинку.
	var built := _built()
	for panel: MeshInstance3D in (built["paint"] as Array):
		var material := panel.material_override as StandardMaterial3D
		if not check(material != null, "у окрашиваемой панели есть материал"):
			continue
		check_equal(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "не стекло")
		check(material.albedo_color.v > 0.25, "не резина: яркость %.2f" % material.albedo_color.v)
	_release(built)


## Точка глаз водителя. Её легко поставить в торпедо или за спинку сиденья, и
## заметно это только запустив игру.
func test_driver_eye_sits_where_a_driver_sits() -> void:
	var built := _built()
	var cabin: Dictionary = built["cabin"]
	var eye: Node3D = cabin["eye"]
	var wheel: Node3D = cabin["wheel"]
	var size := config.body_size
	var half_length := size.z * 0.5

	check(eye.position.y > wheel.position.y, "глаза выше руля")
	check(eye.position.z > wheel.position.z, "и позади него, а не в нём")
	var back := eye.position.z - wheel.position.z
	check(back > 0.25 and back < 0.9, "расстояние до руля как в посадке: %.2f м" % back)
	var up := eye.position.y - wheel.position.y
	check(up > 0.2 and up < 0.65, "глаза над ободом на %.2f м" % up)

	# Глаза внутри габарита кабины, а не в стене и не в кузове.
	check(absf(eye.position.x) < size.x * 0.5, "глаза внутри ширины кабины")
	check(eye.position.z < 0.0, "кабина в передней половине машины")
	check(eye.position.z > -half_length, "и не перед бампером")
	check(eye.position.y < size.y * 0.9 + config.body_offset.y, "не в крыше")

	# Водитель слева: движение правостороннее.
	check(eye.position.x < 0.0, "руль левый")
	check_near(eye.position.x, wheel.position.x, 0.001, "глаза над рулём по ширине")
	_release(built)


func test_cabin_exposes_the_controls_it_animates() -> void:
	var built := _built()
	var cabin: Dictionary = built["cabin"]
	for key: String in ["root", "wheel", "lever", "eye", "radio_light"]:
		check(cabin.has(key) and cabin[key] != null, "кабина отдаёт узел %s" % key)
	_release(built)


## Освобождает собранную машину целиком. Узлы сборщика никогда не попадают в
## дерево, поэтому free(), а не queue_free(): отложенное удаление до простоя
## тут не срабатывает, и движок на выходе сообщает об утёкших RID.
func _release(built: Dictionary) -> void:
	# Колёса собираются отдельными узлами и детьми кузова не становятся: в
	# игре их подхватывает физика. Освобождать их надо руками.
	for wheel: Variant in built.get("wheels", []):
		if wheel is Node and is_instance_valid(wheel):
			(wheel as Node).free()
	var chassis: Variant = built.get("chassis")
	if chassis is Node and is_instance_valid(chassis):
		(chassis as Node).free()


func _all_children(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in node.get_children():
		out.append(child)
		out.append_array(_all_children(child))
	return out
