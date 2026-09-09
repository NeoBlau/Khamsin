class_name ContractGenerator
extends RefCounted
## Генератор заказов.
##
## Доска в посёлке не хранится в сейве: она выводится из сида, идентификатора
## посёлка и номера дня. Поэтому сохранение весит килобайты, а перезагрузка не
## позволяет перебрать удачный заказ — это осознанное решение, а не экономия.

## Средняя маршевая скорость, по которой считается срок доставки, м/с.
const CRUISE_SPEED := 11.0
## Сколько дней предложение висит на доске.
const OFFER_LIFETIME_DAYS := 2

## Что где грузят. Ключ — вид поселения, значение — пары «груз, вес».
const CARGO_BY_KIND: Dictionary[Settlement.Kind, Array] = {
	Settlement.Kind.CITY: [
		["electronics", 1.0], ["medicine", 0.9], ["lab_glass", 0.7],
		["cement", 0.8], ["water", 0.6], ["drill_parts", 0.7],
	],
	Settlement.Kind.OASIS: [
		["produce", 1.2], ["water", 1.0], ["livestock_feed", 0.9], ["medicine", 0.4],
	],
	Settlement.Kind.FARM: [
		["produce", 1.4], ["livestock_feed", 1.1], ["water", 0.7],
	],
	Settlement.Kind.MINE: [
		["drill_parts", 1.3], ["cement", 1.2], ["fuel_drums", 1.0], ["water", 0.5],
	],
	Settlement.Kind.STATION: [
		["lab_glass", 1.3], ["electronics", 1.0], ["medicine", 0.8], ["fuel_drums", 0.5],
	],
	Settlement.Kind.OUTPOST: [
		["fuel_drums", 1.1], ["cement", 0.9], ["water", 0.9], ["electronics", 0.5],
	],
	Settlement.Kind.WELL: [
		["water", 1.4], ["fuel_drums", 0.8], ["livestock_feed", 0.6],
	],
	Settlement.Kind.CAMP: [
		["water", 1.0], ["produce", 0.8], ["livestock_feed", 0.9], ["fuel_drums", 0.6],
	],
	Settlement.Kind.RUIN: [
		["unmarked_crate", 1.0],
	],
}

## Уровни срочности: множитель к сроку и к оплате.
const URGENCY: Array[Array] = [
	["обычный", 2.1, 1.0],
	["срочный", 1.45, 1.35],
	["горящий", 1.12, 1.9],
]


## Заказы, которые висят в посёлке в этот день. Всегда одни и те же для данного
## сида, посёлка и дня.
static func offers_for(origin: Settlement, day: int) -> Array[Contract]:
	var out: Array[Contract] = []
	if origin == null or origin.contract_slots <= 0:
		return out
	var destinations := _destinations(origin)
	if destinations.is_empty():
		return out
	for slot: int in origin.contract_slots:
		var contract := _make(origin, destinations, day, slot)
		if contract != null:
			out.append(contract)
	return out


static func _destinations(origin: Settlement) -> Array[Settlement]:
	var out: Array[Settlement] = []
	for settlement: Settlement in World.settlements:
		if settlement.id == origin.id:
			continue
		out.append(settlement)
	return out


static func _make(
	origin: Settlement, destinations: Array[Settlement], day: int, slot: int
) -> Contract:
	var rng := Rng.local(Rng.hash_string(String(origin.id)), day, slot)

	# Ближние посёлки выпадают чаще дальних: в жизни возят соседям, а рейс
	# через полкарты — событие, а не рутина.
	var weights := PackedFloat32Array()
	for settlement: Settlement in destinations:
		var distance := origin.position.distance_to(settlement.position)
		weights.append(1.0 / (1.0 + distance / 4000.0))
	var destination: Settlement = Rng.pick_weighted(destinations, weights, rng)
	if destination == null:
		return null

	var cargo_id := _pick_cargo(origin, destination, rng)
	var cargo := Catalog.cargo(cargo_id)
	if cargo == null:
		return null

	var config := Catalog.vehicle(GameState.vehicle_id)
	var mass_limit := config.cargo_mass_limit if config != null else 4000.0
	var volume_limit := config.cargo_volume_limit if config != null else 20.0
	# Партия не должна заведомо не влезать: заказ, который невозможно взять,
	# засоряет доску и раздражает.
	var by_mass := int(mass_limit * 0.85 / maxf(cargo.mass, 1.0))
	var by_volume := int(volume_limit * 0.85 / maxf(cargo.volume, 0.05))
	var cap := maxi(1, mini(by_mass, by_volume))
	var units := rng.randi_range(maxi(1, cap / 4), cap)

	var route_length := World.route_distance(origin.id, destination.id)
	if route_length <= 1.0:
		route_length = origin.position.distance_to(destination.position)

	var urgency_index := _roll_urgency(rng)
	var urgency: Array = URGENCY[urgency_index]
	var travel_hours := route_length / CRUISE_SPEED / 3600.0

	var contract := Contract.new()
	contract.id = StringName("%s-%d-%d" % [origin.id, day, slot])
	contract.cargo_id = cargo_id
	contract.units = units
	contract.origin_id = origin.id
	contract.destination_id = destination.id
	contract.issuer = origin.faction
	contract.issuer_name = _issuer_name(origin, rng)
	contract.route_length = route_length
	contract.offered_at_hours = float(day - 1) * GameState.HOURS_PER_DAY + 6.0
	contract.expires_at_hours = contract.offered_at_hours + float(OFFER_LIFETIME_DAYS) * 24.0
	contract.deadline_hours = contract.offered_at_hours + travel_hours * float(urgency[1]) + 4.0
	contract.payout = _payout(cargo, units, route_length, float(urgency[2]))
	contract.deposit = snappedf(cargo.value * float(units) * 0.12, 5.0)
	if urgency_index > 0:
		contract.flags.append(&"urgent")
	if cargo.restricted:
		contract.flags.append(&"restricted")
	if cargo.heat_sensitivity > 0.5:
		contract.flags.append(&"cold")
	if cargo.fragility > 0.6:
		contract.flags.append(&"fragile")
	return contract


static func _roll_urgency(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	if roll < 0.62:
		return 0
	if roll < 0.9:
		return 1
	return 2


static func _pick_cargo(
	origin: Settlement, destination: Settlement, rng: RandomNumberGenerator
) -> StringName:
	var table: Array = CARGO_BY_KIND.get(origin.kind, CARGO_BY_KIND[Settlement.Kind.OUTPOST])
	var items: Array = []
	var weights := PackedFloat32Array()
	for entry: Array in table:
		var id := StringName(entry[0])
		var cargo := Catalog.cargo(id)
		if cargo == null:
			continue
		if cargo.restricted and not bool(GameState.flag(&"licence_restricted", false)):
			continue
		items.append(id)
		var weight := float(entry[1])
		# Скоропортящееся не повезут через полкарты — это никому не выгодно.
		if cargo.decay_per_hour > 0.005:
			var distance := origin.position.distance_to(destination.position)
			weight *= clampf(1.0 - distance / 14000.0, 0.15, 1.0)
		weights.append(weight)
	if items.is_empty():
		return &"water"
	return Rng.pick_weighted(items, weights, rng)


static func _payout(cargo: CargoType, units: int, route_length: float, urgency: float) -> float:
	var kilometres := route_length / 1000.0
	var tonnes := cargo.mass * float(units) / 1000.0
	var base := Config.contract_rate_per_km * kilometres
	var mass_factor := 1.0 + tonnes * 0.22
	var risk := 1.0 + cargo.fragility * 0.65 + cargo.heat_sensitivity * 0.35
	if cargo.restricted:
		risk += 0.9
	return snappedf(base * mass_factor * risk * urgency, 5.0)


static func _issuer_name(origin: Settlement, rng: RandomNumberGenerator) -> String:
	var names: Array[String] = [
		"Диспетчерская «Хамсин»", "Абу Рашид и сыновья", "Кооператив Вади",
		"Северная логистика", "Хаджар-транс", "Семья Мансур", "Склад №4",
	]
	if origin.faction == &"company":
		names = ["Компания «Хуфра-Ресурс»", "Отдел снабжения", "Инженерная служба"]
	elif origin.faction == &"nomads":
		names = ["Старейшина Айн-Диба", "Семья Мансур", "Кооператив Вади"]
	return Rng.pick(names, rng)
