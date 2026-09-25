class_name EasterEggs
extends Node3D
## Находки.
##
## Десять мест в эрге, где стоит что-то, чего там быть не должно. Они не
## отмечены на карте, не выдаются заданием и не светятся: единственный способ
## их найти — свернуть с маршрута. Это и есть весь их смысл, и поэтому они
## расставлены руками в data/story/easter_eggs.json, а не сгенерированы: место
## должно быть таким, чтобы до него хотелось доехать.
##
## Найденное записывается в прохождение и попадает в журнал. Повторно
## сообщение не приходит — найденное остаётся найденным.

signal found(id: StringName, name: String)

const DATA_PATH := "res://data/story/easter_eggs.json"
const BUILD_RADIUS := 320.0
const DROP_RADIUS := 420.0

var target: Node3D

var _eggs: Array[Dictionary] = []
var _live: Dictionary = {}
var _poll: float = 0.0


func begin(follow: Node3D) -> void:
	target = follow
	_load()
	set_process(true)


func _load() -> void:
	_eggs.clear()
	var text := FileAccess.get_file_as_string(DATA_PATH)
	if text.is_empty():
		push_warning("Находки: %s не читается" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		push_warning("Находки: %s не разобран" % DATA_PATH)
		return
	for entry: Variant in parsed as Array:
		_eggs.append(entry as Dictionary)


func all() -> Array[Dictionary]:
	if _eggs.is_empty():
		_load()
	return _eggs


static func is_found(id: StringName) -> bool:
	return bool(GameState.flag(StringName("found_%s" % id)))


static func found_count() -> int:
	var total := 0
	for entry: Dictionary in EasterEggs.new().all():
		if is_found(entry["id"]):
			total += 1
	return total


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.5
	var here := target.global_position
	for entry: Dictionary in all():
		var id := StringName(entry["id"])
		var at: Array = entry["at"]
		var spot := Vector2(float(at[0]), float(at[1]))
		var distance := Vector2(here.x, here.z).distance_to(spot)
		if distance < BUILD_RADIUS and not _live.has(id):
			_spawn(id, entry, spot)
		elif distance > DROP_RADIUS and _live.has(id):
			_drop(id)
		if distance < float(entry.get("radius", 24.0)):
			_discover(id, entry)


func _spawn(id: StringName, entry: Dictionary, spot: Vector2) -> void:
	var node := EasterEggProps.build(StringName(entry.get("prop", "")), Rng.hash_string(String(id)))
	if node == null:
		return
	node.position = Vector3(spot.x, World.height(spot.x, spot.y), spot.y)
	add_child(node)
	_live[id] = node


func _drop(id: StringName) -> void:
	var node: Node3D = _live.get(id)
	if node != null and is_instance_valid(node):
		node.queue_free()
	_live.erase(id)


## Находка засчитывается один раз. Ночные — только ночью: каменный круг днём
## это просто камни, и сообщать о нём днём значит испортить находку.
func _discover(id: StringName, entry: Dictionary) -> void:
	if is_found(id):
		return
	if bool(entry.get("night_only", false)) and not GameState.is_night():
		return
	GameState.set_flag(StringName("found_%s" % id), true)
	var journal: Array = GameState.flag(&"found_notes", [])
	journal.append({"id": String(id), "name": entry.get("name", ""), "note": entry.get("journal", "")})
	GameState.set_flag(&"found_notes", journal)
	EventBus.notify(String(entry.get("note", "Вы что-то нашли")))
	found.emit(id, String(entry.get("name", "")))
