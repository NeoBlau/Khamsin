class_name Condition
extends RefCounted
## Условия в данных сюжета.
##
## Никакого разбора выражений: условие — это словарь с известными ключами.
## Парсер языка внутри JSON выглядит гибче ровно до первой опечатки, после
## которой ветка молча не срабатывает и никто не понимает почему. Здесь
## неизвестный ключ громко ругается.

const KEYS: PackedStringArray = [
	"flag", "not_flag", "money_at_least", "money_below", "day_at_least",
	"deliveries_at_least", "reputation", "chapter", "beat_done", "has_upgrade",
	"carrying", "settlement", "all", "any", "not",
]


## Пустое условие истинно: в данных это самый частый случай.
static func evaluate(condition: Variant, context: Dictionary = {}) -> bool:
	if condition == null:
		return true
	if typeof(condition) == TYPE_BOOL:
		return condition
	if typeof(condition) != TYPE_DICTIONARY:
		push_warning("Condition: ожидался объект, получено %s" % type_string(typeof(condition)))
		return false

	var data := condition as Dictionary
	for key: String in data.keys():
		if not KEYS.has(key):
			push_warning("Condition: неизвестный ключ '%s'" % key)
			return false
		if not _check(key, data[key], context):
			return false
	return true


static func _check(key: String, value: Variant, context: Dictionary) -> bool:
	match key:
		"flag":
			return bool(GameState.flag(StringName(value), false))
		"not_flag":
			return not bool(GameState.flag(StringName(value), false))
		"money_at_least":
			return GameState.money >= float(value)
		"money_below":
			return GameState.money < float(value)
		"day_at_least":
			return GameState.day >= int(value)
		"deliveries_at_least":
			return int(GameState.stats.get("deliveries", 0)) >= int(value)
		"reputation":
			var spec := value as Dictionary
			var faction := StringName(spec.get("faction", "guild"))
			return GameState.reputation_of(faction) >= float(spec.get("at_least", 0.0))
		"chapter":
			return String(GameState.story.get("chapter", "")) == String(value)
		"beat_done":
			return (GameState.story.get("done_beats", []) as Array).has(String(value))
		"has_upgrade":
			return Upgrades.has(StringName(value))
		"carrying":
			for contract: Contract in GameState.active_contracts():
				if String(contract.cargo_id) == String(value):
					return true
			return false
		"settlement":
			return String(context.get("settlement", "")) == String(value)
		"all":
			for entry: Variant in value as Array:
				if not evaluate(entry, context):
					return false
			return true
		"any":
			for entry: Variant in value as Array:
				if evaluate(entry, context):
					return true
			return false
		"not":
			return not evaluate(value, context)
	return false
