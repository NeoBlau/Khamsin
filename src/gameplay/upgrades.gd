class_name Upgrades
extends RefCounted
## Улучшения машины.
##
## Каждое улучшение — это набор поправок к конфигурации. Правки применяются не
## к общему объекту из справочника, а к его копии: иначе покупка амортизаторов
## меняла бы характеристики всех машин в игре, включая ещё не купленные.

const PATH := "res://data/world/upgrades.json"

static var _items: Array[Dictionary] = []
static var _loaded: bool = false


static func all() -> Array[Dictionary]:
	if _loaded:
		return _items
	_loaded = true
	_items = []
	if not FileAccess.file_exists(PATH):
		push_error("Upgrades: нет %s" % PATH)
		return _items
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Upgrades: %s — ожидался массив" % PATH)
		return _items
	for entry: Variant in parsed as Array:
		if typeof(entry) == TYPE_DICTIONARY:
			_items.append(entry as Dictionary)
	return _items


static func find(id: StringName) -> Dictionary:
	for item: Dictionary in all():
		if StringName(item.get("id", "")) == id:
			return item
	return {}


static func owned() -> Array:
	return GameState.vehicle.get("upgrades", [])


static func has(id: StringName) -> bool:
	return owned().has(String(id))


static func buy(id: StringName) -> bool:
	var item := find(id)
	if item.is_empty():
		return false
	if has(id):
		EventBus.notify("Уже стоит", &"warning")
		return false
	var price := float(item.get("price", 0.0))
	if not GameState.spend(price):
		EventBus.notify("Не хватает денег: нужно %s" % Settings.format_money(price), &"warning")
		return false
	var list: Array = owned()
	list.append(String(id))
	GameState.vehicle["upgrades"] = list
	EventBus.notify("Установлено: %s" % item.get("name", id))
	return true


## Копия конфигурации со всеми купленными улучшениями.
static func configure(base: VehicleConfig) -> VehicleConfig:
	var config := clone(base)
	for id: Variant in owned():
		var item := find(StringName(id))
		if item.is_empty():
			continue
		_apply(config, item.get("effects", {}))
	return config


## Насколько установленное оборудование гасит удары по грузу, 0..1.
static func shock_absorption() -> float:
	var total := 0.0
	for id: Variant in owned():
		total += float(find(StringName(id)).get("shock_absorption", 0.0))
	return clampf(total, 0.0, 0.8)


static func _apply(config: VehicleConfig, effects: Dictionary) -> void:
	for key: String in effects.keys():
		var value := float(effects[key])
		match key:
			"torque_scale":
				var curve := PackedVector2Array()
				for point: Vector2 in config.torque_curve:
					curve.append(Vector2(point.x, point.y * (1.0 + value)))
				config.torque_curve = curve
			"tire_width":
				for spec: VehicleConfig.WheelSpec in config.wheels:
					spec.width += value
			"diff_lock_locked":
				config.diff_lock_locked = clampf(config.diff_lock_locked + value, 0.0, 0.99)
			"diff_lock_open":
				config.diff_lock_open = clampf(config.diff_lock_open + value, 0.0, 0.99)
			_:
				if not key in config:
					push_warning("Upgrades: неизвестная поправка '%s'" % key)
					continue
				config.set(key, float(config.get(key)) + value)


## Ручное копирование: `duplicate()` не проходит по массиву колёс, потому что
## это объекты вложенного класса, а не ресурсы.
static func clone(source: VehicleConfig) -> VehicleConfig:
	var config: VehicleConfig = source.duplicate(true)
	var wheels: Array[VehicleConfig.WheelSpec] = []
	for spec: VehicleConfig.WheelSpec in source.wheels:
		var copy := VehicleConfig.WheelSpec.new()
		copy.position = spec.position
		copy.steered = spec.steered
		copy.driven = spec.driven
		copy.handbrake = spec.handbrake
		copy.radius = spec.radius
		copy.width = spec.width
		copy.inertia = spec.inertia
		copy.brake_bias = spec.brake_bias
		wheels.append(copy)
	config.wheels = wheels
	config.torque_curve = source.torque_curve.duplicate()
	config.gear_ratios = source.gear_ratios.duplicate()
	return config
