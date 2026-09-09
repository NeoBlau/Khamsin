class_name ContractBoard
extends RefCounted
## Приём и сдача заказов.
##
## Вся работа идёт через GameState: сама доска ничего не хранит, кроме памяти о
## том, какие предложения уже отработаны. Так её можно звать откуда угодно —
## из интерфейса, из сюжета, из теста, — не таская ссылку на объект.


## Что сейчас висит в посёлке: сгенерированные предложения минус взятые,
## сданные и просроченные.
static func offers(settlement: Settlement) -> Array[Contract]:
	var out: Array[Contract] = []
	if settlement == null:
		return out
	var now := GameState.total_hours()
	var retired := _retired()
	for day: int in range(maxi(1, GameState.day - ContractGenerator.OFFER_LIFETIME_DAYS + 1), GameState.day + 1):
		for contract: Contract in ContractGenerator.offers_for(settlement, day):
			if retired.has(String(contract.id)):
				continue
			if GameState.find_contract(contract.id) != null:
				continue
			if now > contract.expires_at_hours:
				continue
			out.append(contract)
	# Сюжетные заказы кладутся поверх обычных и всегда идут первыми.
	for contract: Contract in _story_offers(settlement):
		out.push_front(contract)
	return out


static func _story_offers(settlement: Settlement) -> Array[Contract]:
	var out: Array[Contract] = []
	var pending: Array = GameState.story.get("pending_contracts", [])
	for entry: Variant in pending:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var contract := Contract.from_dict(entry as Dictionary)
		if contract.origin_id != settlement.id:
			continue
		if GameState.find_contract(contract.id) != null:
			continue
		if _retired().has(String(contract.id)):
			continue
		out.append(contract)
	return out


static func _retired() -> Array:
	return GameState.story.get("retired_contracts", [])


static func _retire(id: StringName) -> void:
	var retired: Array = _retired()
	if not retired.has(String(id)):
		retired.append(String(id))
	GameState.story["retired_contracts"] = retired


## Может ли машина взять этот груз прямо сейчас.
## Возвращает пустую строку, если может, иначе причину отказа.
static func rejection_reason(contract: Contract, vehicle: VehicleBody) -> String:
	var config := vehicle.config if vehicle != null else Catalog.vehicle(GameState.vehicle_id)
	if config == null:
		return "нет машины"
	if contract.has_flag(&"restricted") and not bool(GameState.flag(&"licence_restricted", false)):
		return "нужна лицензия на особые грузы"
	if not GameState.can_afford(contract.deposit):
		return "не хватает %s на залог" % Settings.format_money(contract.deposit)
	var mass := GameState.carried_mass() + contract.total_mass()
	if mass > config.cargo_mass_limit:
		return "перегруз: %.0f кг сверх нормы" % (mass - config.cargo_mass_limit)
	var volume := GameState.carried_volume() + contract.total_volume()
	if volume > config.cargo_volume_limit:
		return "не влезет в кузов: не хватает %.1f м³" % (volume - config.cargo_volume_limit)
	return ""


static func can_accept(contract: Contract, vehicle: VehicleBody) -> bool:
	return rejection_reason(contract, vehicle).is_empty()


## Берёт заказ: списывает залог, кладёт груз в кузов, ставит метку на карте.
static func accept(contract: Contract, vehicle: VehicleBody) -> bool:
	var reason := rejection_reason(contract, vehicle)
	if not reason.is_empty():
		EventBus.notify(reason, &"warning")
		return false
	GameState.spend(contract.deposit)
	contract.state = Contract.State.ACTIVE
	contract.integrity = 1.0
	# Часы пошли с погрузки, а не с момента, когда заказ повесили на доску.
	contract.deadline_hours = GameState.total_hours() + contract.duration_hours
	GameState.add_contract(contract)
	GameState.discover_settlement(contract.destination_id)
	if vehicle != null:
		vehicle.refresh_cargo_mass()
	EventBus.contract_accepted.emit(contract.id)
	EventBus.notify("Принят заказ: %s → %s" % [
		contract.cargo().display_name, World.settlement(contract.destination_id).display_name
	])
	return true


## Заказы, которые можно сдать в этом посёлке прямо сейчас.
static func deliverable(settlement: Settlement) -> Array[Contract]:
	var out: Array[Contract] = []
	if settlement == null:
		return out
	for contract: Contract in GameState.active_contracts():
		if contract.destination_id == settlement.id:
			out.append(contract)
	return out


## Сдаёт заказ. Возвращает словарь с разбором расчёта — интерфейсу есть что
## показать, а игроку понятно, за что именно не доплатили.
static func deliver(contract: Contract, vehicle: VehicleBody) -> Dictionary:
	var now := GameState.total_hours()
	var gross := contract.payout
	var after_integrity := gross * contract.integrity_multiplier()
	var payout := contract.payout_at(now)
	var late_hours := maxf(0.0, now - contract.deadline_hours)
	var damage := contract.damage_charge()
	var returned := maxf(contract.deposit - damage, 0.0)

	contract.state = Contract.State.DELIVERED
	_retire(contract.id)
	GameState.remove_contract(contract.id)
	GameState.add_money(payout + returned)
	GameState.stats["deliveries"] = int(GameState.stats.get("deliveries", 0)) + 1

	var on_time := late_hours <= 0.0
	var reputation := 1.6 if on_time else 0.4
	reputation *= contract.integrity_multiplier()
	if contract.integrity < 0.75:
		reputation -= 1.2
	GameState.add_reputation(contract.issuer, reputation)

	if vehicle != null:
		vehicle.refresh_cargo_mass()
	EventBus.contract_completed.emit(contract.id, payout, on_time)

	return {
		"payout": payout,
		"gross": gross,
		"integrity_loss": gross - after_integrity,
		"late_loss": after_integrity - payout,
		"late_hours": late_hours,
		"deposit_returned": returned,
		"damage_charge": damage,
		"on_time": on_time,
		"reputation": reputation,
	}


## Отказ от заказа в пути. Залог сгорает, репутация падает — но иногда это
## дешевле, чем везти битое стекло через полкарты.
static func abandon(contract: Contract, vehicle: VehicleBody, reason: StringName = &"abandoned") -> void:
	contract.state = Contract.State.FAILED
	_retire(contract.id)
	GameState.remove_contract(contract.id)
	GameState.stats["failures"] = int(GameState.stats.get("failures", 0)) + 1
	GameState.add_reputation(contract.issuer, -2.5)
	if vehicle != null:
		vehicle.refresh_cargo_mass()
	EventBus.contract_failed.emit(contract.id, reason)
	EventBus.notify("Заказ провален: %s" % contract.cargo().display_name, &"error")


## Снимает просроченные заказы. Зовётся раз в игровой час.
static func expire_overdue() -> void:
	var now := GameState.total_hours()
	for contract: Contract in GameState.active_contracts():
		# Даём сутки сверх срока: опоздание — это штраф, а не мгновенный провал.
		if now > contract.deadline_hours + 24.0:
			abandon(contract, null, &"expired")
		elif contract.integrity <= 0.02:
			abandon(contract, null, &"destroyed")
