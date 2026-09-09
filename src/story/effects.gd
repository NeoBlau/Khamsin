class_name Effects
extends RefCounted
## Последствия выборов и сюжетных битов.
##
## Тот же принцип, что и в условиях: фиксированный набор ключей вместо
## встроенного языка. Всё, что сюжет умеет менять в мире, перечислено здесь —
## и это заодно исчерпывающий список того, на что вообще влияет разговор.

const KEYS: PackedStringArray = [
	"set_flag", "clear_flag", "money", "reputation", "notify", "dialogue",
	"offer_contract", "discover", "advance_hours", "damage_cargo", "beat",
]


static func apply(effects: Variant, context: Dictionary = {}) -> void:
	if effects == null or typeof(effects) != TYPE_DICTIONARY:
		return
	for key: String in (effects as Dictionary).keys():
		if not KEYS.has(key):
			push_warning("Effects: неизвестный ключ '%s'" % key)
			continue
		_apply_one(key, (effects as Dictionary)[key], context)


static func _apply_one(key: String, value: Variant, context: Dictionary) -> void:
	match key:
		"set_flag":
			if typeof(value) == TYPE_ARRAY:
				for name: Variant in value as Array:
					GameState.set_flag(StringName(name), true)
			else:
				GameState.set_flag(StringName(value), true)
		"clear_flag":
			GameState.set_flag(StringName(value), false)
		"money":
			GameState.add_money(float(value))
		"reputation":
			var spec := value as Dictionary
			GameState.add_reputation(
				StringName(spec.get("faction", "guild")), float(spec.get("amount", 0.0))
			)
		"notify":
			EventBus.notify(String(value))
		"dialogue":
			EventBus.dialogue_requested.emit(StringName(value))
		"offer_contract":
			_offer_contract(value as Dictionary, context)
		"discover":
			GameState.discover_settlement(StringName(value))
		"advance_hours":
			GameState.advance_time(float(value))
		"damage_cargo":
			for contract: Contract in GameState.active_contracts():
				contract.apply_damage(float(value))
		"beat":
			EventBus.beat_reached.emit(StringName(value))


## Кладёт сюжетный заказ на доску названного посёлка. Он не генерируется
## случайно и не исчезает по сроку предложения — его ждут.
static func _offer_contract(spec: Dictionary, _context: Dictionary) -> void:
	var contract := Contract.new()
	contract.id = StringName(spec.get("id", "story_%d" % GameState.day))
	contract.story_id = contract.id
	contract.cargo_id = StringName(spec.get("cargo", "unmarked_crate"))
	contract.units = int(spec.get("units", 1))
	contract.origin_id = StringName(spec.get("from", ""))
	contract.destination_id = StringName(spec.get("to", ""))
	contract.issuer = StringName(spec.get("issuer", "guild"))
	contract.issuer_name = String(spec.get("issuer_name", "Частный заказ"))
	contract.route_length = World.route_distance(contract.origin_id, contract.destination_id)
	contract.payout = float(spec.get("payout", 1200.0))
	contract.deposit = float(spec.get("deposit", 0.0))
	contract.offered_at_hours = GameState.total_hours()
	contract.expires_at_hours = contract.offered_at_hours + float(spec.get("expires_in", 96.0))
	contract.deadline_hours = contract.offered_at_hours + float(spec.get("hours", 24.0))
	for flag: Variant in spec.get("flags", []):
		contract.flags.append(StringName(flag))

	var pending: Array = GameState.story.get("pending_contracts", [])
	pending.append(contract.to_dict())
	GameState.story["pending_contracts"] = pending
	GameState.discover_settlement(contract.destination_id)
	EventBus.contract_offered.emit(contract.id)
