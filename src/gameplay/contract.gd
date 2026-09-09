class_name Contract
extends Resource
## Заказ на перевозку: откуда, куда, что, за сколько и к какому часу.
##
## Целостность груза (`integrity`) живёт здесь, а не в машине: груз может
## переехать в другой кузов, а обязательства перед заказчиком останутся теми же.

enum State { OFFERED, ACTIVE, DELIVERED, FAILED, EXPIRED }

@export var id: StringName = &""
@export var cargo_id: StringName = &""
@export var units: int = 1
@export var origin_id: StringName = &""
@export var destination_id: StringName = &""
@export var issuer: StringName = &"guild"
@export var issuer_name: String = ""

## Длина маршрута по трассам, метры. По ней считаются деньги и срок.
@export var route_length: float = 0.0
@export var payout: float = 0.0
## Залог, который курьер вносит при приёмке и получает назад с грузом.
@export var deposit: float = 0.0
## Абсолютное игровое время в часах, к которому груз ждут. Назначается в момент
## приёмки: до этого срок хранится длительностью в `duration_hours`.
@export var deadline_hours: float = 0.0
## Сколько часов даётся на рейс с момента погрузки.
@export var duration_hours: float = 8.0
@export var offered_at_hours: float = 0.0
## До какого часа предложение висит на доске.
@export var expires_at_hours: float = 0.0

@export_range(0.0, 1.0) var integrity: float = 1.0
@export var state: State = State.OFFERED
## Непустой, если заказ поставлен сюжетом, а не генератором.
@export var story_id: StringName = &""
@export var flags: Array[StringName] = []


func cargo() -> CargoType:
	return Catalog.cargo(cargo_id)


func total_mass() -> float:
	var type := cargo()
	return (type.mass if type != null else 0.0) * float(units)


func total_volume() -> float:
	var type := cargo()
	return (type.volume if type != null else 0.0) * float(units)


func declared_value() -> float:
	var type := cargo()
	return (type.value if type != null else 0.0) * float(units)


func has_flag(flag: StringName) -> bool:
	return flags.has(flag)


func hours_left(now_hours: float) -> float:
	return deadline_hours - now_hours


func is_late(now_hours: float) -> bool:
	return now_hours > deadline_hours


## Сколько заплатят прямо сейчас. Опоздание срезает долю за каждый час, битый
## груз — пропорционально утрате. Ниже нуля не уходим: заказчик не доплачивает
## курьеру за испорченный товар, он просто не платит.
func payout_at(now_hours: float) -> float:
	var amount := payout * integrity_multiplier()
	var late := maxf(0.0, now_hours - deadline_hours)
	if late > 0.0:
		amount *= maxf(0.0, 1.0 - Config.late_penalty_per_hour * late)
	return maxf(0.0, amount)


## Целостность влияет нелинейно: царапины прощают, половину груза — нет.
func integrity_multiplier() -> float:
	if integrity >= 0.98:
		return 1.0
	return clampf(pow(integrity, 1.8), 0.0, 1.0)


## Сколько удержат из залога за порчу.
func damage_charge() -> float:
	return declared_value() * (1.0 - integrity) * 0.6


func apply_damage(amount: float) -> void:
	if amount <= 0.0 or state != State.ACTIVE:
		return
	var before := integrity
	integrity = clampf(integrity - amount, 0.0, 1.0)
	if absf(before - integrity) > 0.0005:
		EventBus.cargo_damaged.emit(id, integrity)


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"cargo_id": String(cargo_id),
		"units": units,
		"origin_id": String(origin_id),
		"destination_id": String(destination_id),
		"issuer": String(issuer),
		"issuer_name": issuer_name,
		"route_length": route_length,
		"payout": payout,
		"deposit": deposit,
		"deadline_hours": deadline_hours,
		"duration_hours": duration_hours,
		"offered_at_hours": offered_at_hours,
		"expires_at_hours": expires_at_hours,
		"integrity": integrity,
		"state": int(state),
		"story_id": String(story_id),
		"flags": flags.map(func(f: StringName) -> String: return String(f)),
	}


static func from_dict(data: Dictionary) -> Contract:
	var c := Contract.new()
	c.id = StringName(data.get("id", ""))
	c.cargo_id = StringName(data.get("cargo_id", ""))
	c.units = int(data.get("units", 1))
	c.origin_id = StringName(data.get("origin_id", ""))
	c.destination_id = StringName(data.get("destination_id", ""))
	c.issuer = StringName(data.get("issuer", "guild"))
	c.issuer_name = String(data.get("issuer_name", ""))
	c.route_length = float(data.get("route_length", 0.0))
	c.payout = float(data.get("payout", 0.0))
	c.deposit = float(data.get("deposit", 0.0))
	c.deadline_hours = float(data.get("deadline_hours", 0.0))
	c.duration_hours = float(data.get("duration_hours", 8.0))
	c.offered_at_hours = float(data.get("offered_at_hours", 0.0))
	c.expires_at_hours = float(data.get("expires_at_hours", 0.0))
	c.integrity = float(data.get("integrity", 1.0))
	c.state = int(data.get("state", State.OFFERED))
	c.story_id = StringName(data.get("story_id", ""))
	var flags: Array[StringName] = []
	for f: Variant in data.get("flags", []):
		flags.append(StringName(f))
	c.flags = flags
	return c
