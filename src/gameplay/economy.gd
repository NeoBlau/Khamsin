class_name Economy
extends RefCounted
## Деньги: топливо, ремонт, ночлег, резина.
##
## Цены не берутся с потолка и не хранятся в сейве — они выводятся из места и
## дня. Дальний посёлок дороже не потому, что «так задумано», а потому что у
## него в описании стоит наценка: солярку туда возит такой же курьер.

## Разброс дневной цены топлива, доля. Небольшой, но заметный: выгоднее
## заправляться там, где дешевле, а не там, где встал.
const FUEL_DAILY_SWING := 0.12
## Цена комплекта резины.
const TIRE_SET_PRICE := 1850.0
## Сколько часов занимает замена комплекта.
const TIRE_SET_HOURS := 1.5


static func fuel_price(settlement: Settlement) -> float:
	if settlement == null:
		return Config.fuel_price_per_litre * Config.remote_fuel_markup
	var swing := Rng.range_from(
		Rng.hash_string(String(settlement.id)),
		GameState.day,
		Rng.hash_string("fuel"),
		1.0 - FUEL_DAILY_SWING,
		1.0 + FUEL_DAILY_SWING
	)
	return Config.fuel_price_per_litre * settlement.fuel_markup * swing


## Заправка. Возвращает {litres, cost} — если денег хватило только на часть,
## заливается часть: отказать курьеру в десяти литрах было бы издевательством.
static func refuel(settlement: Settlement, vehicle: VehicleBody, litres: float) -> Dictionary:
	if settlement == null or not settlement.has_service(&"fuel"):
		EventBus.notify("Здесь нет топлива", &"warning")
		return {"litres": 0.0, "cost": 0.0}
	var price := fuel_price(settlement)
	var room := vehicle.config.fuel_capacity - vehicle.fuel
	var affordable := GameState.money / maxf(price, 0.001)
	var amount := minf(minf(litres, room), affordable)
	if amount <= 0.05:
		EventBus.notify("Не на что заправляться", &"warning")
		return {"litres": 0.0, "cost": 0.0}
	var cost := amount * price
	GameState.spend(cost)
	vehicle.refuel(amount)
	vehicle.sync_to_state()
	EventBus.notify("Залито %.0f л за %s" % [amount, Settings.format_money(cost)])
	return {"litres": amount, "cost": cost}


static func full_tank_cost(settlement: Settlement, vehicle: VehicleBody) -> float:
	return (vehicle.config.fuel_capacity - vehicle.fuel) * fuel_price(settlement)


## Смета на ремонт: по узлу — состояние, цена и время.
static func repair_quote(vehicle: VehicleBody) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(_line(&"engine", "Двигатель", vehicle.engine_health, 5200.0, 6.0))
	out.append(_line(&"suspension", "Подвеска", vehicle.suspension_health, 3400.0, 4.0))
	out.append(_line(&"body", "Кузов и рама", vehicle.body_health, 2600.0, 3.0))
	var wear := 0.0
	for wheel: VehicleWheel in vehicle.wheels:
		wear = maxf(wear, wheel.wear)
	out.append(_line(&"tires", "Резина", 1.0 - wear, TIRE_SET_PRICE, TIRE_SET_HOURS))
	return out


static func _line(
	id: StringName, title: String, condition: float, full_price: float, full_hours: float
) -> Dictionary:
	var damage := clampf(1.0 - condition, 0.0, 1.0)
	# Мелкая просадка чинится непропорционально дёшево, глубокая — дороже:
	# переборка узла стоит своих денег вне зависимости от того, насколько он убит.
	var cost := full_price * pow(damage, 0.75) + (Config.repair_labour_rate if damage > 0.02 else 0.0)
	return {
		"id": id,
		"title": title,
		"condition": condition,
		"cost": snappedf(cost, 5.0),
		"hours": full_hours * damage + (0.5 if damage > 0.02 else 0.0),
		"needed": damage > 0.02,
	}


static func repair(settlement: Settlement, vehicle: VehicleBody, component: StringName) -> bool:
	if settlement == null or not settlement.has_service(&"repair"):
		EventBus.notify("Здесь не чинят", &"warning")
		return false
	for line: Dictionary in repair_quote(vehicle):
		if StringName(line["id"]) != component:
			continue
		if not bool(line["needed"]):
			EventBus.notify("%s в порядке" % line["title"])
			return false
		if not GameState.spend(float(line["cost"])):
			EventBus.notify("Не хватает %s" % Settings.format_money(float(line["cost"])), &"warning")
			return false
		vehicle.repair(component, 1.0)
		vehicle.sync_to_state()
		GameState.advance_time(float(line["hours"]))
		EventBus.notify("%s: сделано за %.1f ч" % [line["title"], float(line["hours"])])
		return true
	return false


static func repair_all_cost(vehicle: VehicleBody) -> float:
	var total := 0.0
	for line: Dictionary in repair_quote(vehicle):
		if bool(line["needed"]):
			total += float(line["cost"])
	return total


## Ночлег: время идёт быстро, машина не расходует топливо, груз продолжает
## портиться. Спать с медикаментами в кузове — плохая идея, и это честно.
static func rest(settlement: Settlement, hours: float) -> bool:
	if settlement == null or not settlement.has_service(&"bunk"):
		EventBus.notify("Здесь негде ночевать", &"warning")
		return false
	var cost := rest_cost(settlement, hours)
	if not GameState.spend(cost):
		EventBus.notify("Не хватает на ночлег", &"warning")
		return false
	GameState.advance_time(hours)
	EventBus.notify("Отдых %.0f ч, %s" % [hours, Settings.format_money(cost)])
	return true


static func rest_cost(settlement: Settlement, hours: float) -> float:
	var base := 22.0 * settlement.fuel_markup if settlement != null else 40.0
	return snappedf(base * hours, 5.0)


## Скидка от репутации: своим отпускают дешевле. Прямой и понятный смысл
## копить отношения с фракцией.
static func discount(settlement: Settlement) -> float:
	if settlement == null:
		return 0.0
	var reputation := GameState.reputation_of(settlement.faction)
	return clampf(reputation / 100.0 * 0.15, -0.1, 0.15)
