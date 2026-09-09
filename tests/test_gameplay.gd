extends TestCase
## Заказы, деньги, улучшения.
##
## Всё это чистая логика без сцены, поэтому проверяется быстро и подробно.
## Отдельный акцент на детерминированности доски: сейв хранит сид и день, а не
## список предложений, и если генератор поплывёт, старые сохранения покажут
## другие заказы.

const SEED := 20260907


func before_each() -> void:
	if not World.is_ready or Rng.world_seed != SEED:
		Rng.set_world_seed(SEED)
		World.build_now(SEED)
	GameState.new_game(SEED)


func _origin() -> Settlement:
	return World.settlement(&"mahatta")


func test_board_is_deterministic() -> void:
	var first := ContractGenerator.offers_for(_origin(), 3)
	var second := ContractGenerator.offers_for(_origin(), 3)
	check_equal(first.size(), second.size(), "одно и то же число заказов")
	for i: int in first.size():
		check_equal(first[i].id, second[i].id, "идентификатор заказа %d" % i)
		check_equal(first[i].cargo_id, second[i].cargo_id, "груз заказа %d" % i)
		check_near(first[i].payout, second[i].payout, 0.001, "оплата заказа %d" % i)


func test_board_changes_from_day_to_day() -> void:
	var monday := ContractGenerator.offers_for(_origin(), 3)
	var tuesday := ContractGenerator.offers_for(_origin(), 4)
	var same := 0
	for i: int in mini(monday.size(), tuesday.size()):
		if monday[i].id == tuesday[i].id:
			same += 1
	check_equal(same, 0, "на следующий день доска должна обновиться")


func test_offers_fit_in_the_truck() -> void:
	var config := Catalog.vehicle(GameState.vehicle_id)
	for day: int in range(1, 6):
		for settlement: Settlement in World.settlements:
			for contract: Contract in ContractGenerator.offers_for(settlement, day):
				check(
					contract.total_mass() <= config.cargo_mass_limit,
					"%s: масса %.0f выше грузоподъёмности" % [contract.id, contract.total_mass()]
				)
				check(
					contract.total_volume() <= config.cargo_volume_limit,
					"%s: объём %.1f выше вместимости" % [contract.id, contract.total_volume()]
				)
				if not failures.is_empty():
					return


func test_offers_are_worth_taking() -> void:
	# Оплата обязана покрывать хотя бы солярку, иначе заказ — это ловушка,
	# а не выбор. Считаем по паспортному расходу на маршевом режиме.
	var config := Catalog.vehicle(GameState.vehicle_id)
	for contract: Contract in ContractGenerator.offers_for(_origin(), 2):
		var kilometres := contract.route_length / 1000.0
		var litres := kilometres * 0.42
		var fuel_cost := litres * Config.fuel_price_per_litre * 1.4
		check(
			contract.payout > fuel_cost * 1.5,
			"%s: оплата %.0f против топлива на %.0f" % [contract.id, contract.payout, fuel_cost]
		)
		check_greater(contract.deadline_hours, contract.offered_at_hours, "срок должен быть в будущем")
	check_greater(float(config.fuel_capacity), 100.0, "бак у стартовой машины")


func test_payout_falls_with_damage_and_lateness() -> void:
	var contract := ContractGenerator.offers_for(_origin(), 1)[0]
	var on_time := contract.payout_at(contract.deadline_hours - 1.0)
	check_near(on_time, contract.payout, 0.01, "целый груз в срок оплачивается полностью")

	contract.integrity = 0.5
	var damaged := contract.payout_at(contract.deadline_hours - 1.0)
	check(damaged < on_time * 0.4, "половина груза должна стоить заметно меньше половины оплаты")

	contract.integrity = 1.0
	var late := contract.payout_at(contract.deadline_hours + 3.0)
	check(late < on_time, "опоздание должно резать оплату")
	check_greater(late, 0.0, "но не в ноль за три часа")

	var hopeless := contract.payout_at(contract.deadline_hours + 40.0)
	check_near(hopeless, 0.0, 0.001, "через двое суток платить уже не за что")


func test_accepting_and_delivering_moves_money() -> void:
	var contract := ContractGenerator.offers_for(_origin(), 1)[0]
	var before := GameState.money
	check(ContractBoard.accept(contract, null), "заказ должен приниматься")
	check_near(GameState.money, before - contract.deposit, 0.01, "залог списывается при приёмке")
	check_equal(GameState.active_contracts().size(), 1, "заказ должен стать активным")

	var report := ContractBoard.deliver(contract, null)
	check(bool(report["on_time"]), "сдача сразу после приёмки — это в срок")
	check_near(
		GameState.money, before + float(report["payout"]), 0.01,
		"после сдачи возвращается залог и приходит оплата"
	)
	check_equal(GameState.active_contracts().size(), 0, "сданный заказ уходит из активных")
	check_equal(int(GameState.stats["deliveries"]), 1, "счётчик доставок")


func test_overload_is_refused() -> void:
	var config := Catalog.vehicle(GameState.vehicle_id)
	var contract := ContractGenerator.offers_for(_origin(), 1)[0]
	contract.units = int(config.cargo_mass_limit / contract.cargo().mass) + 20
	var reason := ContractBoard.rejection_reason(contract, null)
	check(reason.contains("Перегруз") or reason.contains("перегруз") or reason.contains("влезет"),
		"перегруз должен быть назван причиной, получено: '%s'" % reason)


func test_deposit_must_be_affordable() -> void:
	var contract := ContractGenerator.offers_for(_origin(), 1)[0]
	contract.deposit = GameState.money + 1000.0
	check(
		ContractBoard.rejection_reason(contract, null).contains("залог"),
		"без денег на залог заказ брать нельзя"
	)


func test_restricted_cargo_needs_a_licence() -> void:
	var contract := Contract.new()
	contract.id = &"test_restricted"
	contract.cargo_id = &"unmarked_crate"
	contract.units = 1
	contract.flags.append(&"restricted")
	check(
		ContractBoard.rejection_reason(contract, null).contains("лицензия"),
		"особый груз без лицензии брать нельзя"
	)
	GameState.set_flag(&"licence_restricted", true)
	check(
		not ContractBoard.rejection_reason(contract, null).contains("лицензия"),
		"с лицензией запрет должен сниматься"
	)


func test_overdue_contracts_are_dropped() -> void:
	var contract := ContractGenerator.offers_for(_origin(), 1)[0]
	ContractBoard.accept(contract, null)
	GameState.day += 4
	ContractBoard.expire_overdue()
	check_equal(GameState.active_contracts().size(), 0, "просроченный заказ должен сняться")
	check_equal(int(GameState.stats["failures"]), 1, "счётчик провалов")
	check(GameState.reputation_of(contract.issuer) < 0.0, "за провал репутация падает")


func test_destroyed_cargo_fails_the_contract() -> void:
	var contract := ContractGenerator.offers_for(_origin(), 1)[0]
	ContractBoard.accept(contract, null)
	contract.apply_damage(1.0)
	ContractBoard.expire_overdue()
	check_equal(GameState.active_contracts().size(), 0, "уничтоженный груз снимает заказ")


func test_fuel_is_dearer_far_from_the_city() -> void:
	var city := Economy.fuel_price(World.settlement(&"mahatta"))
	var ruin := Economy.fuel_price(World.settlement(&"mahjar"))
	check_greater(ruin, city * 1.5, "в глуши солярка должна быть заметно дороже")
	check_between(city, 1.0, 2.0, "цена в городе, дх за литр")


func test_repair_quote_scales_with_damage() -> void:
	var vehicle := VehicleBody.new()
	vehicle.config_id = &"tabuk_6t"
	vehicle.player_controlled = false
	host.add_child(vehicle)
	vehicle.engine_health = 0.5
	var quote := Economy.repair_quote(vehicle)
	var engine: Dictionary = {}
	for line: Dictionary in quote:
		if line["id"] == &"engine":
			engine = line
	check(not engine.is_empty(), "в смете должен быть двигатель")
	check(bool(engine["needed"]), "убитый наполовину мотор надо чинить")
	check_greater(float(engine["cost"]), 100.0, "и это должно стоить денег")
	check_greater(float(engine["hours"]), 0.5, "и времени")
	vehicle.engine_health = 1.0
	for line: Dictionary in Economy.repair_quote(vehicle):
		if line["id"] == &"engine":
			check(not bool(line["needed"]), "целый мотор чинить не надо")
	vehicle.queue_free()


func test_upgrades_change_a_copy_not_the_catalogue() -> void:
	var base := Catalog.vehicle(&"tabuk_6t")
	var original_torque := base.peak_torque()
	GameState.money = 50000.0
	check(Upgrades.buy(&"turbo_rebuild"), "улучшение должно покупаться")
	check(Upgrades.has(&"turbo_rebuild"), "и появляться в списке установленных")

	var tuned := Upgrades.configure(base)
	check_greater(tuned.peak_torque(), original_torque * 1.1, "турбина должна добавить момента")
	check_near(
		base.peak_torque(), original_torque, 0.001,
		"справочная машина меняться не должна — иначе поплывут все остальные"
	)
	check_equal(tuned.wheels.size(), base.wheels.size(), "колёса должны скопироваться")

	check(not Upgrades.buy(&"turbo_rebuild"), "дважды одно и то же не ставят")
	GameState.money = 10.0
	check(not Upgrades.buy(&"long_travel"), "без денег улучшение не купить")


func test_tire_upgrade_widens_the_wheels_of_the_copy() -> void:
	var base := Catalog.vehicle(&"tabuk_6t")
	var original_width := base.wheels[0].width
	GameState.money = 50000.0
	Upgrades.buy(&"sand_tires")
	var tuned := Upgrades.configure(base)
	check_greater(tuned.wheels[0].width, original_width, "песчаные шины шире")
	check_near(base.wheels[0].width, original_width, 0.0001, "оригинал не тронут")
