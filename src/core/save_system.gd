extends Node
## Сохранения: слоты, автосейв, миграция старых форматов.
##
## Формат — обычный JSON, читаемый глазами. Это осознанный размен: файл больше
## бинарного и его легко подправить читом, зато баг в сейве видно за минуту, а
## не за день с дизассемблером. Для коммерческого релиза сюда добавляется
## подпись, но структура остаётся той же.

const DIR := "user://saves"
const SLOT_COUNT := 6
const AUTOSAVE_SLOT := 0

var _autosave_timer: float = 0.0
var _last_error: String = ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
	set_process(true)


func _process(delta: float) -> void:
	if not GameState.is_running:
		return
	if Settings.autosave_minutes <= 0.0:
		return
	_autosave_timer += delta
	if _autosave_timer >= Settings.autosave_minutes * 60.0:
		_autosave_timer = 0.0
		save_to_slot(AUTOSAVE_SLOT)


## Живое состояние машины — топливо, износ, положение — живёт в узле сцены и
## попадает в GameState только по требованию. Автосохранение обязано попросить
## само, иначе оно запишет состояние получасовой давности.
func _sync_vehicle() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(&"player_vehicle"):
		if node.has_method(&"sync_to_state"):
			node.call(&"sync_to_state")


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [DIR, slot]


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func last_error() -> String:
	return _last_error


func save_to_slot(slot: int) -> bool:
	_last_error = ""
	_sync_vehicle()
	var payload := {
		"format": Config.SAVE_FORMAT_VERSION,
		"game_version": Config.VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"state": GameState.serialize(),
	}
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		_last_error = "не открыть %s (код %d)" % [slot_path(slot), FileAccess.get_open_error()]
		push_error("SaveSystem: " + _last_error)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	EventBus.game_saved.emit(slot)
	return true


func load_from_slot(slot: int) -> bool:
	_last_error = ""
	var data := read_slot(slot)
	if data.is_empty():
		return false
	var state: Variant = data.get("state")
	if typeof(state) != TYPE_DICTIONARY:
		_last_error = "в слоте %d нет секции state" % slot
		return false
	GameState.deserialize(state as Dictionary)
	EventBus.game_loaded.emit(slot)
	return true


## Читает и мигрирует слот, ничего не применяя. Используется и загрузкой, и
## экраном выбора сейва, которому нужны только заголовки.
func read_slot(slot: int) -> Dictionary:
	_last_error = ""
	if not slot_exists(slot):
		_last_error = "слот %d пуст" % slot
		return {}
	var text := FileAccess.get_file_as_string(slot_path(slot))
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_last_error = "слот %d повреждён" % slot
		push_error("SaveSystem: " + _last_error)
		return {}
	return migrate(parsed as Dictionary)


## Краткая сводка для списка сохранений, без разбора всего состояния.
func slot_summary(slot: int) -> Dictionary:
	var data := read_slot(slot)
	if data.is_empty():
		return {}
	var state: Dictionary = data.get("state", {})
	return {
		"slot": slot,
		"saved_at": data.get("saved_at", ""),
		"day": state.get("day", 1),
		"hour": state.get("time_of_day", 0.0),
		"money": state.get("money", 0.0),
		"chapter": state.get("story", {}).get("chapter", ""),
		"odometer": state.get("vehicle", {}).get("odometer", 0.0),
		"version": data.get("game_version", "?"),
	}


func delete_slot(slot: int) -> void:
	if slot_exists(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))


## Подтягивает старые сейвы к текущему формату. Каждый шаг — отдельная функция,
## они выполняются подряд, поэтому сейв версии 1 доезжает до сегодняшней через
## все промежуточные состояния.
func migrate(data: Dictionary) -> Dictionary:
	var format: int = int(data.get("format", 1))
	while format < Config.SAVE_FORMAT_VERSION:
		match format:
			1:
				_migrate_1_to_2(data)
			2:
				_migrate_2_to_3(data)
			_:
				push_warning("SaveSystem: не знаю, как мигрировать формат %d" % format)
				break
		format += 1
		data["format"] = format
	return data


func _migrate_1_to_2(data: Dictionary) -> void:
	# В первом формате давление в шинах было одним числом на всю машину.
	var vehicle: Dictionary = data.get("state", {}).get("vehicle", {})
	if vehicle.has("tire_pressure") and not vehicle.has("tire_pressures"):
		var single: float = float(vehicle["tire_pressure"])
		vehicle["tire_pressures"] = [single, single, single, single]
		vehicle.erase("tire_pressure")


func _migrate_2_to_3(data: Dictionary) -> void:
	# Репутация стала пофракционной вместо одного числа.
	var state: Dictionary = data.get("state", {})
	if typeof(state.get("reputation")) in [TYPE_FLOAT, TYPE_INT]:
		var value: float = float(state["reputation"])
		state["reputation"] = {"guild": value, "nomads": 0.0, "company": 0.0}
