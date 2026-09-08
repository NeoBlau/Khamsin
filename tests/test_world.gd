extends TestCase
## Мир: рельеф, площадки посёлков, дорожная сеть.
##
## Отдельно проверяется детерминированность — на ней держится и формат сейва
## (мы храним сид, а не миллион вершин), и возможность вообще воспроизвести
## чужой баг по номеру мира.

const SEED := 20260907


func before_each() -> void:
	if not World.is_ready or Rng.world_seed != SEED:
		Rng.set_world_seed(SEED)
		World.build_now(SEED)


func test_world_builds() -> void:
	check(World.is_ready, "мир должен собраться")
	check(World.field != null, "рельеф должен существовать")
	check_greater(float(World.settlements.size()), 5.0, "посёлков должно быть достаточно для сети")
	check(World.routes.is_built(), "дорожная сеть должна быть построена")
	check_greater(float(World.routes.routes.size()), 6.0, "маршрутов должно быть больше, чем посёлков")


func test_height_is_deterministic() -> void:
	var samples := PackedFloat32Array()
	for i: int in 64:
		var x := lerpf(-9000.0, 9000.0, float(i) / 63.0)
		samples.append(World.field.height(x, x * 0.31))
	var other := TerrainField.new(SEED)
	other.apply_config()
	other.settlements = World.field.settlements
	other.routes = World.routes
	for i: int in 64:
		var x := lerpf(-9000.0, 9000.0, float(i) / 63.0)
		check_near(other.height(x, x * 0.31), samples[i], 0.001, "высота при том же сиде должна совпадать")
		if not failures.is_empty():
			return


func test_different_seeds_make_different_worlds() -> void:
	var other := TerrainField.new(SEED + 1)
	other.apply_config()
	var difference := 0.0
	for i: int in 48:
		var x := lerpf(-8000.0, 8000.0, float(i) / 47.0)
		difference += absf(other.base_height(x, 1200.0) - World.field.base_height(x, 1200.0))
	check_greater(difference / 48.0, 5.0, "другой сид должен давать заметно другой рельеф")


func test_dunes_are_asymmetric() -> void:
	# Идём поперёк дюнного поля и меряем подъёмы и спуски. У настоящих дюн
	# наветренный склон длинный и пологий, подветренный — короткий и крутой,
	# поэтому распределение уклонов обязано быть несимметричным.
	var field := TerrainField.new(SEED)
	field.apply_config()
	var direction := field.wind_direction
	var up_slopes := PackedFloat32Array()
	var down_slopes := PackedFloat32Array()
	var step := 4.0
	var previous := field.dune_height(0.0, 0.0)
	for i: int in range(1, 1200):
		var point := direction * (float(i) * step)
		var current := field.dune_height(point.x, point.y)
		var slope := (current - previous) / step
		if slope > 0.01:
			up_slopes.append(slope)
		elif slope < -0.01:
			down_slopes.append(-slope)
		previous = current
	check_greater(float(up_slopes.size()), 50.0, "на профиле должны быть подъёмы")
	check_greater(float(down_slopes.size()), 50.0, "на профиле должны быть спуски")
	var mean_up := _mean(up_slopes)
	var mean_down := _mean(down_slopes)
	check_greater(
		mean_down / maxf(mean_up, 0.001), 1.6,
		"подветренный склон должен быть круче наветренного: %.3f против %.3f" % [mean_down, mean_up]
	)


func test_dune_slopes_stay_below_the_angle_of_repose() -> void:
	# Песок не держит склон круче примерно 34°. Если модель выдаёт больше,
	# машина будет утыкаться в стены, которых в пустыне не бывает.
	var field := TerrainField.new(SEED)
	field.apply_config()
	var steepest := 0.0
	for i: int in 400:
		var x := lerpf(-6000.0, 6000.0, float(i) / 399.0)
		for j: int in 12:
			var z := lerpf(-6000.0, 6000.0, float(j) / 11.0)
			if field.dune_mask(x, z) < 0.6:
				continue
			steepest = maxf(steepest, field.slope(x, z, 6.0))
	# 0.75 по тангенсу — это 37°. Песок держит примерно до 34°, небольшой запас
	# оставлен на то, что уклон меряется по сетке, а не аналитически.
	check(steepest < 0.75, "максимальный уклон в дюнах: %.2f (tg угла)" % steepest)


func test_settlements_stand_on_flat_ground() -> void:
	for settlement: Settlement in World.settlements:
		var centre := settlement.position
		var lowest := INF
		var highest := -INF
		for i: int in 8:
			var angle := TAU * float(i) / 8.0
			var offset := Vector2(cos(angle), sin(angle)) * settlement.radius * 0.3
			var h := World.field.height(centre.x + offset.x, centre.y + offset.y)
			lowest = minf(lowest, h)
			highest = maxf(highest, h)
		check(
			highest - lowest < 3.0,
			"площадка %s должна быть ровной, перепад %.1f м" % [settlement.id, highest - lowest]
		)


func test_routes_are_longer_than_a_straight_line_but_not_absurd() -> void:
	for route: RouteNetwork.Route in World.routes.routes:
		var from := World.settlement(route.from_id)
		var to := World.settlement(route.to_id)
		var straight := from.position.distance_to(to.position)
		check_greater(route.length, straight * 0.95, "маршрут %s не может быть короче прямой" % route.id)
		check(
			route.length < straight * 2.2,
			"маршрут %s подозрительно длинный: %.0f при прямой %.0f" % [route.id, route.length, straight]
		)


func test_routes_avoid_the_steepest_ground() -> void:
	var field := TerrainField.new(SEED)
	field.apply_config()
	var on_route := 0.0
	var samples := 0
	for route: RouteNetwork.Route in World.routes.routes:
		for i: int in range(0, route.points.size(), 4):
			var p := route.points[i]
			on_route += field.slope(p.x, p.z, 20.0)
			samples += 1
	var average_route := on_route / maxf(float(samples), 1.0)

	var random := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for _i: int in samples:
		var x := rng.randf_range(-8000.0, 8000.0)
		var z := rng.randf_range(-8000.0, 8000.0)
		random += field.slope(x, z, 20.0)
	var average_random := random / maxf(float(samples), 1.0)

	check(
		average_route < average_random,
		"дорога должна идти положе случайного места: %.3f против %.3f" % [average_route, average_random]
	)


func test_road_surface_is_a_graded_track() -> void:
	for route: RouteNetwork.Route in World.routes.routes:
		var middle := route.points[route.points.size() / 2]
		if not check_equal(
			World.field.surface_id_at(middle.x, middle.z), &"track",
			"на полотне маршрута %s должна быть накатка" % route.id
		):
			return

	# И наоборот: там, где дорог нет, накатки быть не может. Точку ищем честно —
	# проверяя расстояние до сети, а не надеясь, что рядом ничего не проходит.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var checked := 0
	for _i: int in 400:
		var x := rng.randf_range(-8000.0, 8000.0)
		var z := rng.randf_range(-8000.0, 8000.0)
		if World.routes.nearest(x, z).x <= World.routes.half_width + 5.0:
			continue
		checked += 1
		if not check(
			World.field.surface_id_at(x, z) != &"track",
			"накатка нашлась в стороне от всех трасс: (%.0f, %.0f)" % [x, z]
		):
			return
	check_greater(float(checked), 100.0, "проверить нужно было заметное число точек вне дорог")


func test_road_flattens_the_ground_under_itself() -> void:
	var route: RouteNetwork.Route = World.routes.routes[0]
	var index := route.points.size() / 2
	var p := route.points[index]
	check_near(World.field.height(p.x, p.z), p.y, 0.6, "полотно должно совпадать с высотой трассы")


func test_map_border_is_impassable() -> void:
	var inside := World.field.height(0.0, 0.0)
	var edge := World.field.height(Config.world_extent - 60.0, 0.0)
	check_greater(edge - inside, 120.0, "за границей должна вставать непроезжая гряда")
	check(not World.field.is_inside(Config.world_extent - 100.0, 0.0), "край карты не считается игровой зоной")


func test_surface_lookup_covers_the_map() -> void:
	var counts: Dictionary[StringName, int] = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for _i: int in 3000:
		var x := rng.randf_range(-8500.0, 8500.0)
		var z := rng.randf_range(-8500.0, 8500.0)
		var id := World.field.surface_id_at(x, z)
		counts[id] = counts.get(id, 0) + 1
	check_greater(float(counts.size()), 2.0, "покрытий должно быть больше двух, иначе карта однообразна")
	var sand: int = int(counts.get(&"sand_soft", 0)) + int(counts.get(&"sand_firm", 0))
	check_greater(float(sand) / 3000.0, 0.15, "песка в пустыне должно быть заметно")
	check(float(sand) / 3000.0 < 0.95, "но не только песок")


func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v: float in values:
		total += v
	return total / float(values.size())
