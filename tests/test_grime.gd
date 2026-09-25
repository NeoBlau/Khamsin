extends TestCase
## Грязь, верблюды и мойка.
##
## Главное правило этой механики: верблюжий плевок не смывается нигде, кроме
## оазиса Дяди Вали. Если он начнёт сходить от обычной воды, крюк через оазис
## теряет смысл, а вместе с ним и половина причины туда ездить.

var vehicle: VehicleBody
var grime: Grime
var weather: Weather


func before_each() -> void:
	Catalog.ensure_loaded()
	GameState.new_game(20260907)
	vehicle = VehicleBody.new()
	vehicle.config_id = &"tabuk_6t"
	vehicle.player_controlled = false
	host.add_child(vehicle)
	var built := ChassisBuilder.build(vehicle.config)
	var wheel_nodes: Array[Node3D] = built["wheels"]
	for node: Node3D in wheel_nodes:
		vehicle.add_child(node)
	vehicle.attach_visuals(built["chassis"], wheel_nodes, built)
	weather = Weather.new()
	host.add_child(weather)
	grime = Grime.new()
	vehicle.add_child(grime)
	grime.attach(vehicle, weather)


func _ensure_world() -> void:
	if not World.is_built_for(20260907):
		Rng.set_world_seed(20260907)
		World.build_now(20260907)


func after_each() -> void:
	if vehicle != null and is_instance_valid(vehicle):
		vehicle.queue_free()
	if weather != null and is_instance_valid(weather):
		weather.queue_free()
	vehicle = null
	grime = null
	weather = null


# --- Пыль -------------------------------------------------------------------


func test_a_clean_truck_starts_clean() -> void:
	check_near(grime.dust, 0.0, 0.001, "новая машина не грязная")
	check_equal(grime.splat_count(), 0, "и не заплёванная")
	check_near(grime.visibility_penalty(), 0.0, 0.001, "через чистое стекло видно всё")


func test_driving_makes_the_truck_dusty() -> void:
	var before := grime.dust
	# Пять километров по пыльному грунту: на ста и борта, и стекло упёрлись бы
	# в потолок, и разницы между ними было бы не видно.
	vehicle.odometer += 5000.0
	grime._process(0.0)
	check(grime.dust > before, "пыль накопилась: %.3f" % grime.dust)
	check(grime.glass_dust > grime.dust, "на стекле её больше, чем на бортах")


func test_dust_never_runs_past_one() -> void:
	vehicle.odometer += 10_000_000.0
	grime._process(0.0)
	check(grime.dust <= 1.0, "пыль не выходит за единицу: %.3f" % grime.dust)
	check(grime.glass_dust <= 1.0, "и на стекле тоже")


func test_a_sandstorm_dirties_a_parked_truck() -> void:
	weather.dust = 0.9
	var before := grime.dust
	# Час стояния в буре.
	grime._process(Config.seconds_per_game_hour)
	check(grime.dust > before, "в буре машина пылится и на стоянке: %.3f" % grime.dust)


# --- Плевки -----------------------------------------------------------------


func test_water_does_not_take_camel_spit_off() -> void:
	grime.add_splat(Vector3(0.9, 0.6, -1.0))
	grime.add_splat(Vector3(-0.9, 0.5, 0.4))
	vehicle.odometer += 50000.0
	grime._process(0.0)
	check_equal(grime.splat_count(), 2, "плевков два")
	check(grime.dust > 0.0, "и пыль есть")

	var washed := grime.wash(false)
	check_near(grime.dust, 0.0, 0.001, "пыль смылась")
	check_equal(int(washed["splats"]), 0, "а плевки водой не берутся")
	check_equal(grime.splat_count(), 2, "они на месте")


func test_the_oasis_takes_the_spit_off() -> void:
	grime.add_splat(Vector3(0.9, 0.6, -1.0))
	grime.add_splat(Vector3(-0.9, 0.5, 0.4))
	var washed := grime.wash(true)
	check_equal(int(washed["splats"]), 2, "щётками сняли оба")
	check_equal(grime.splat_count(), 0, "машина чистая")
	check_near(grime.visibility_penalty(), 0.0, 0.001, "и стекло тоже")


func test_spit_costs_you_visibility() -> void:
	var clean := grime.visibility_penalty()
	for i: int in 4:
		grime.add_splat(Vector3(0.0, 0.8, -1.2 + float(i) * 0.2))
	check(grime.visibility_penalty() > clean, "через заплёванное стекло видно хуже")
	check(grime.visibility_penalty() <= 1.0, "но не вслепую")


func test_grime_survives_a_save() -> void:
	grime.add_splat(Vector3(0.7, 0.5, -0.9), 1.3)
	vehicle.odometer += 40000.0
	grime._process(0.0)
	var snapshot := grime.serialize()
	var dust := grime.dust

	var fresh := Grime.new()
	vehicle.add_child(fresh)
	fresh.attach(vehicle, weather)
	fresh.deserialize(snapshot)
	check_near(fresh.dust, dust, 0.0001, "пыль восстановилась")
	check_equal(fresh.splat_count(), 1, "и плевок на месте")
	var entry: Dictionary = fresh.splats[0]
	check_near(float(entry["x"]), 0.7, 0.0001, "ровно там же, где был")
	fresh.queue_free()


# --- Полёт плевка -----------------------------------------------------------


## Клякса должна оказаться на обшивке, а не внутри кузова: иначе её не видно
## и вся механика становится числом в меню.
func test_spit_sticks_to_the_outside_of_the_body() -> void:
	var size := vehicle.config.body_size * 0.5
	var offset := vehicle.config.body_offset
	for inside: Vector3 in [
		Vector3(0.1, 0.0, 0.0), Vector3(0.0, 0.2, 0.3), Vector3(-0.2, -0.1, -0.5)
	]:
		var on := CamelSpit._to_shell(vehicle, inside + offset)
		var local := on - offset
		var reach := maxf(
			maxf(absf(local.x) / size.x, absf(local.y) / size.y), absf(local.z) / size.z
		)
		check_near(reach, 1.0, 0.001, "клякса легла на габарит, а не внутрь него")


func test_camel_leads_its_target() -> void:
	# Верблюд целится туда, где машина будет, а не туда, где она есть.
	# Иначе попасть в едущую машину он не сможет никогда.
	var moving := VehicleBody.new()
	moving.config_id = &"tabuk_6t"
	moving.player_controlled = false
	host.add_child(moving)
	moving.global_position = Vector3(20.0, 0.0, 0.0)
	moving.linear_velocity = Vector3(0.0, 0.0, -18.0)
	var spit := CamelSpit.new()
	var aim := spit._aim(Vector3.ZERO, moving)
	check(aim.length() > 0.0, "плевок летит")
	check(aim.z < -1.0, "с упреждением по ходу машины: z = %.2f" % aim.z)
	check(aim.y > 0.0, "и по дуге, а не по прямой")
	spit.free()
	moving.queue_free()


# --- Стада ------------------------------------------------------------------


func test_herds_are_deterministic_from_the_seed() -> void:
	# Сид мира здесь не трогаем: он общий на весь прогон, и его подмена
	# оставляет следующим тестам рельеф от одного сида с номером от другого.
	_ensure_world()
	var first := CamelHerd.new()
	host.add_child(first)
	first._plan_places()
	var second := CamelHerd.new()
	host.add_child(second)
	second._plan_places()
	check_equal(first.herd_places().size(), second.herd_places().size(), "стад столько же")
	var same := 0
	for i: int in first.herd_places().size():
		var a: Vector2 = first.herd_places()[i]["at"]
		var b: Vector2 = second.herd_places()[i]["at"]
		if a.is_equal_approx(b):
			same += 1
	check_equal(same, first.herd_places().size(), "и стоят они на тех же местах")
	first.queue_free()
	second.queue_free()


func test_herds_stay_inside_the_map() -> void:
	_ensure_world()
	var herd := CamelHerd.new()
	host.add_child(herd)
	herd._plan_places()
	var half := Config.world_size() * 0.5
	for place: Dictionary in herd.herd_places():
		var at: Vector2 = place["at"]
		check(absf(at.x) < half and absf(at.y) < half,
			"стадо внутри карты: %s" % at)
		check(int(place["size"]) >= CamelHerd.MIN_HERD, "в стаде не меньше двух")
		check(int(place["size"]) <= CamelHerd.MAX_HERD, "и не больше семи")
	herd.queue_free()


# --- Деньги -----------------------------------------------------------------


func test_full_wash_costs_more_when_there_is_spit() -> void:
	var oasis := World.settlement(&"wilsacom_oasis")
	if not check(oasis != null, "оазис Дяди Вали есть на карте"):
		return
	check(oasis.has_service(&"wash_full"), "и в нём моют с щётками")
	var plain := Economy.wash_cost(oasis, grime, true)
	grime.add_splat(Vector3(0.8, 0.5, -0.8))
	grime.add_splat(Vector3(-0.8, 0.5, 0.8))
	var with_spit := Economy.wash_cost(oasis, grime, true)
	check(with_spit > plain, "за плевки берут отдельно: %.0f против %.0f" % [with_spit, plain])


func test_only_the_oasis_offers_the_full_wash() -> void:
	var full: Array[StringName] = []
	for settlement: Settlement in World.settlements:
		if settlement.has_service(&"wash_full"):
			full.append(settlement.id)
	check_equal(full.size(), 1, "полная мойка ровно одна на карте: %s" % [full])
	if full.size() == 1:
		check_equal(full[0], &"wilsacom_oasis", "и она у Дяди Вали")
