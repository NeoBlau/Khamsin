class_name Catalog
extends RefCounted
## Справочники, загружаемые из `res://data`. Читаются один раз и живут до
## выхода: это чистые данные, их не нужно перезагружать на каждую сцену.

const CARGO_DIR := "res://data/cargo"
const VEHICLE_DIR := "res://data/vehicles"

static var _cargo: Dictionary[StringName, CargoType] = {}
static var _vehicles: Dictionary[StringName, VehicleConfig] = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_cargo()
	_load_vehicles()


static func reload() -> void:
	_loaded = false
	_cargo.clear()
	_vehicles.clear()
	ensure_loaded()


static func _load_cargo() -> void:
	for path: String in _json_files(CARGO_DIR):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_ARRAY:
			push_error("Catalog: %s — ожидался массив грузов" % path)
			continue
		for entry: Variant in parsed as Array:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var cargo := CargoType.from_dict(entry as Dictionary)
			if cargo.id == &"":
				push_error("Catalog: груз без id в %s" % path)
				continue
			_cargo[cargo.id] = cargo


static func _load_vehicles() -> void:
	for path: String in _json_files(VEHICLE_DIR):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Catalog: %s — ожидался объект машины" % path)
			continue
		var config := VehicleConfig.from_dict(parsed as Dictionary)
		if config.id == &"":
			push_error("Catalog: машина без id в %s" % path)
			continue
		_vehicles[config.id] = config


static func _json_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Catalog: нет каталога %s" % dir_path)
		return out
	for file_name: String in dir.get_files():
		# В экспортированной сборке .json лежит как есть, но редактор может
		# оставить рядом .import и .uid — их пропускаем.
		if file_name.get_extension().to_lower() == "json":
			out.append(dir_path.path_join(file_name))
	out.sort()
	return out


static func cargo(id: StringName) -> CargoType:
	ensure_loaded()
	return _cargo.get(id)


static func all_cargo() -> Array[CargoType]:
	ensure_loaded()
	var out: Array[CargoType] = []
	for key: StringName in _cargo.keys():
		out.append(_cargo[key])
	return out


static func vehicle(id: StringName) -> VehicleConfig:
	ensure_loaded()
	return _vehicles.get(id)


static func all_vehicles() -> Array[VehicleConfig]:
	ensure_loaded()
	var out: Array[VehicleConfig] = []
	for key: StringName in _vehicles.keys():
		out.append(_vehicles[key])
	return out
