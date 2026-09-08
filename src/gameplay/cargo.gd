class_name CargoType
extends Resource
## Тип груза: что это, сколько весит и что с ним может случиться в дороге.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## Масса одной единицы, кг.
@export var mass: float = 100.0
## Объём одной единицы, м³. Ограничивает загрузку раньше массы у лёгких грузов.
@export var volume: float = 0.5
## Базовая стоимость единицы. От неё считается залог и штраф за порчу.
@export var value: float = 400.0
## 0 — стальные трубы, которым всё равно; 1 — лабораторное стекло.
@export_range(0.0, 1.0) var fragility: float = 0.2
## Чувствительность к жаре. Выше нуля — груз портится днём без рефрижератора.
@export_range(0.0, 1.0) var heat_sensitivity: float = 0.0
## Портится со временем независимо от условий, доля целостности в час.
@export var decay_per_hour: float = 0.0
## Возить без лицензии нельзя, на постах досматривают.
@export var restricted: bool = false
@export var tags: Array[StringName] = []


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


static func from_dict(data: Dictionary) -> CargoType:
	var cargo := CargoType.new()
	cargo.id = StringName(data.get("id", ""))
	cargo.display_name = String(data.get("name", data.get("id", "")))
	cargo.description = String(data.get("description", ""))
	cargo.mass = float(data.get("mass", 100.0))
	cargo.volume = float(data.get("volume", 0.5))
	cargo.value = float(data.get("value", 400.0))
	cargo.fragility = clampf(float(data.get("fragility", 0.2)), 0.0, 1.0)
	cargo.heat_sensitivity = clampf(float(data.get("heat_sensitivity", 0.0)), 0.0, 1.0)
	cargo.decay_per_hour = float(data.get("decay_per_hour", 0.0))
	cargo.restricted = bool(data.get("restricted", false))
	var tags: Array[StringName] = []
	for tag: Variant in data.get("tags", []):
		tags.append(StringName(tag))
	cargo.tags = tags
	return cargo
