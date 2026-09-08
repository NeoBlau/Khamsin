extends Node
## Состояние прохождения: деньги, время, машина, заказы, сюжет.
##
## Здесь нет ни одной ссылки на узлы сцены. Всё, что попадает сюда, обязано
## пережить выгрузку мира и уложиться в JSON — это и есть определение того,
## что считается прогрессом, а что декорацией.

signal time_advanced(total_hours: float)

const HOURS_PER_DAY := 24.0

var is_running: bool = false
var difficulty: StringName = &"normal"

var money: float = 0.0
var day: int = 1
var time_of_day: float = 6.5

var vehicle_id: StringName = &"tabuk_6t"
## Состояние машины между сессиями: топливо, износ, апгрейды, давление в шинах.
var vehicle: Dictionary = {}

var contracts: Array[Contract] = []
var reputation: Dictionary[StringName, float] = {}
var known_settlements: Array[StringName] = []
var story: Dictionary = {}
var stats: Dictionary = {}

## Куда поставить машину при входе в мир. Пусто — стартовая площадка главы.
var spawn_settlement: StringName = &""
var spawn_transform: Transform3D = Transform3D.IDENTITY
var has_spawn_transform: bool = false


func _ready() -> void:
	reset()


func reset() -> void:
	is_running = false
	money = Config.starting_money
	day = 1
	time_of_day = Config.start_hour
	vehicle_id = &"tabuk_6t"
	vehicle = default_vehicle_state()
	contracts.clear()
	reputation = {&"guild": 0.0, &"nomads": 0.0, &"company": 0.0}
	known_settlements = []
	story = {"chapter": &"", "beat": &"", "flags": {}, "seen_dialogues": []}
	stats = {
		"distance_driven": 0.0,
		"fuel_burned": 0.0,
		"deliveries": 0,
		"failures": 0,
		"rollovers": 0,
		"sandstorms_survived": 0,
	}
	spawn_settlement = &""
	has_spawn_transform = false


func default_vehicle_state() -> Dictionary:
	return {
		"fuel": 0.0,  ## заполняется при старте по объёму бака
		"odometer": 0.0,
		"engine_health": 1.0,
		"gearbox_health": 1.0,
		"suspension_health": 1.0,
		"body_health": 1.0,
		"tire_wear": [0.0, 0.0, 0.0, 0.0],
		"tire_pressures": [2.4, 2.4, 2.4, 2.4],
		"upgrades": [],
		"coolant_temp": 60.0,
	}


func new_game(world_seed: int, chosen_difficulty: StringName = &"normal") -> void:
	reset()
	difficulty = chosen_difficulty
	Rng.set_world_seed(world_seed)
	Catalog.ensure_loaded()
	var config := Catalog.vehicle(vehicle_id)
	if config != null:
		vehicle["fuel"] = config.fuel_capacity
	is_running = true


# --- Время -----------------------------------------------------------------

func total_hours() -> float:
	return float(day - 1) * HOURS_PER_DAY + time_of_day


## Двигает часы вперёд. Единственная точка, где меняется время: и вождение, и
## сон в мотеле, и ремонт зовут её, поэтому события «прошёл час» не теряются.
func advance_time(hours: float) -> void:
	if hours <= 0.0:
		return
	var before_hour := floori(total_hours())
	time_of_day += hours
	while time_of_day >= HOURS_PER_DAY:
		time_of_day -= HOURS_PER_DAY
		day += 1
	var after_hour := floori(total_hours())
	for _i: int in mini(after_hour - before_hour, 48):
		EventBus.hour_passed.emit(day, time_of_day)
	time_advanced.emit(total_hours())


func is_night() -> bool:
	return time_of_day < 5.4 or time_of_day > 18.9


# --- Деньги ----------------------------------------------------------------

func add_money(delta: float) -> void:
	if is_zero_approx(delta):
		return
	money += delta
	EventBus.money_changed.emit(money, delta)


func can_afford(amount: float) -> bool:
	return money + 0.001 >= amount


func spend(amount: float) -> bool:
	if not can_afford(amount):
		return false
	add_money(-amount)
	return true


# --- Заказы ----------------------------------------------------------------

func find_contract(id: StringName) -> Contract:
	for c: Contract in contracts:
		if c.id == id:
			return c
	return null


func active_contracts() -> Array[Contract]:
	var out: Array[Contract] = []
	for c: Contract in contracts:
		if c.state == Contract.State.ACTIVE:
			out.append(c)
	return out


func carried_mass() -> float:
	var total := 0.0
	for c: Contract in active_contracts():
		total += c.total_mass()
	return total


func carried_volume() -> float:
	var total := 0.0
	for c: Contract in active_contracts():
		total += c.total_volume()
	return total


func add_contract(contract: Contract) -> void:
	if find_contract(contract.id) != null:
		return
	contracts.append(contract)


func remove_contract(id: StringName) -> void:
	for i: int in contracts.size():
		if contracts[i].id == id:
			contracts.remove_at(i)
			return


# --- Репутация -------------------------------------------------------------

func reputation_of(faction: StringName) -> float:
	return reputation.get(faction, 0.0)


func add_reputation(faction: StringName, delta: float) -> void:
	var value := clampf(reputation_of(faction) + delta, -100.0, 100.0)
	reputation[faction] = value
	EventBus.reputation_changed.emit(faction, value)


# --- Сюжет -----------------------------------------------------------------

func flag(name: StringName, fallback: Variant = false) -> Variant:
	return (story.get("flags", {}) as Dictionary).get(String(name), fallback)


func set_flag(name: StringName, value: Variant = true) -> void:
	var flags: Dictionary = story.get("flags", {})
	flags[String(name)] = value
	story["flags"] = flags
	EventBus.story_flag_set.emit(name, value)


func discover_settlement(id: StringName) -> void:
	if known_settlements.has(id):
		return
	known_settlements.append(id)


# --- Сериализация ----------------------------------------------------------

func serialize() -> Dictionary:
	var contract_data: Array = []
	for c: Contract in contracts:
		contract_data.append(c.to_dict())
	var reputation_data: Dictionary = {}
	for key: StringName in reputation.keys():
		reputation_data[String(key)] = reputation[key]
	return {
		"world_seed": Rng.world_seed,
		"difficulty": String(difficulty),
		"money": money,
		"day": day,
		"time_of_day": time_of_day,
		"vehicle_id": String(vehicle_id),
		"vehicle": vehicle.duplicate(true),
		"contracts": contract_data,
		"reputation": reputation_data,
		"known_settlements": known_settlements.map(func(s: StringName) -> String: return String(s)),
		"story": story.duplicate(true),
		"stats": stats.duplicate(true),
		"spawn_settlement": String(spawn_settlement),
		"spawn_transform": _transform_to_array(spawn_transform) if has_spawn_transform else [],
	}


func deserialize(data: Dictionary) -> void:
	reset()
	Rng.set_world_seed(int(data.get("world_seed", Rng.world_seed)))
	difficulty = StringName(data.get("difficulty", "normal"))
	money = float(data.get("money", Config.starting_money))
	day = int(data.get("day", 1))
	time_of_day = float(data.get("time_of_day", Config.start_hour))
	vehicle_id = StringName(data.get("vehicle_id", "tabuk_6t"))

	var saved_vehicle: Dictionary = data.get("vehicle", {})
	var merged := default_vehicle_state()
	for key: String in saved_vehicle.keys():
		merged[key] = saved_vehicle[key]
	vehicle = merged

	contracts.clear()
	for entry: Variant in data.get("contracts", []):
		if typeof(entry) == TYPE_DICTIONARY:
			contracts.append(Contract.from_dict(entry as Dictionary))

	reputation.clear()
	var saved_reputation: Dictionary = data.get("reputation", {})
	for key: String in saved_reputation.keys():
		reputation[StringName(key)] = float(saved_reputation[key])

	known_settlements.clear()
	for entry: Variant in data.get("known_settlements", []):
		known_settlements.append(StringName(entry))

	story = (data.get("story", story) as Dictionary).duplicate(true)
	stats = (data.get("stats", stats) as Dictionary).duplicate(true)
	spawn_settlement = StringName(data.get("spawn_settlement", ""))
	var xform: Array = data.get("spawn_transform", [])
	has_spawn_transform = xform.size() == 12
	if has_spawn_transform:
		spawn_transform = _array_to_transform(xform)
	Catalog.ensure_loaded()
	is_running = true


func _transform_to_array(t: Transform3D) -> Array:
	return [
		t.basis.x.x, t.basis.x.y, t.basis.x.z,
		t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z,
		t.origin.x, t.origin.y, t.origin.z,
	]


func _array_to_transform(a: Array) -> Transform3D:
	return Transform3D(
		Basis(
			Vector3(a[0], a[1], a[2]),
			Vector3(a[3], a[4], a[5]),
			Vector3(a[6], a[7], a[8])
		),
		Vector3(a[9], a[10], a[11])
	)
