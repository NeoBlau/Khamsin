class_name Dialogue
extends RefCounted
## Разговор: граф узлов с репликами и выборами.
##
## Загружается из `res://data/story/dialogues.json`. Узел — это одна реплика с
## именем говорящего; выборы ведут к другим узлам, проверяют условия и меняют
## мир через Effects. Ветка без выборов идёт по `next`, а без `next` —
## заканчивает разговор.

const PATH := "res://data/story/dialogues.json"

static var _graphs: Dictionary[StringName, Dictionary] = {}
static var _loaded: bool = false

var id: StringName = &""
var _nodes: Dictionary = {}
var _current: String = ""
var _context: Dictionary = {}


static func _load_all() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_warning("Dialogue: нет %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Dialogue: %s — ожидался объект" % PATH)
		return
	for key: String in (parsed as Dictionary).keys():
		_graphs[StringName(key)] = (parsed as Dictionary)[key]


static func reload() -> void:
	_loaded = false
	_graphs.clear()
	_load_all()


static func exists(dialogue_id: StringName) -> bool:
	_load_all()
	return _graphs.has(dialogue_id)


static func open(dialogue_id: StringName, context: Dictionary = {}) -> Dialogue:
	_load_all()
	if not _graphs.has(dialogue_id):
		push_error("Dialogue: нет разговора '%s'" % dialogue_id)
		return null
	var dialogue := Dialogue.new()
	dialogue.id = dialogue_id
	var graph: Dictionary = _graphs[dialogue_id]
	dialogue._nodes = graph.get("nodes", {})
	dialogue._context = context
	dialogue._current = String(graph.get("start", "start"))
	return dialogue


func is_finished() -> bool:
	return _current == "" or not _nodes.has(_current)


func node() -> Dictionary:
	return _nodes.get(_current, {})


func speaker() -> String:
	return String(node().get("speaker", ""))


func text() -> String:
	return String(node().get("text", ""))


## Доступные ответы. Недоступные по условиям не показываются вовсе — список
## вариантов, половина которых серая, читается как упрёк, а не как выбор.
func choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in node().get("choices", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var choice := entry as Dictionary
		if not Condition.evaluate(choice.get("if"), _context):
			continue
		out.append(choice)
	return out


## Продолжает разговор. `index` — номер в списке, который вернул `choices()`.
## Для реплик без выбора индекс игнорируется.
func advance(index: int = -1) -> void:
	var current := node()
	Effects.apply(current.get("effects"), _context)

	var available := choices()
	if available.is_empty():
		_current = String(current.get("next", ""))
		_finish_if_needed()
		return
	var choice: Dictionary = available[clampi(index, 0, available.size() - 1)]
	Effects.apply(choice.get("effects"), _context)
	_current = String(choice.get("goto", ""))
	_finish_if_needed()


func _finish_if_needed() -> void:
	if is_finished():
		var seen: Array = GameState.story.get("seen_dialogues", [])
		if not seen.has(String(id)):
			seen.append(String(id))
			GameState.story["seen_dialogues"] = seen
		EventBus.dialogue_finished.emit(id)
