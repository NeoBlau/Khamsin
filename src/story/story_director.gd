class_name StoryDirector
extends Node
## Главы и биты сюжета.
##
## Бит — это условие и то, что происходит, когда оно выполнилось. Директор
## проверяет биты текущей главы на каждое заметное событие: приезд в посёлок,
## сданный заказ, наступивший час. Никакой очереди и никакого «следующего шага»:
## порядок задаётся условиями, поэтому игрок может выполнить их не подряд и
## ничего не сломается.

const PATH := "res://data/story/chapters.json"

var chapters: Array[Dictionary] = []

var _by_id: Dictionary[StringName, Dictionary] = {}
var _context: Dictionary = {}


func _ready() -> void:
	_load()
	EventBus.settlement_entered.connect(_on_settlement_entered)
	EventBus.settlement_exited.connect(_on_settlement_exited)
	EventBus.contract_completed.connect(_on_contract_completed)
	EventBus.hour_passed.connect(_on_hour_passed)
	if String(GameState.story.get("chapter", "")) == "" and not chapters.is_empty():
		start_chapter(StringName(chapters[0].get("id", "")))
	else:
		evaluate()


func _load() -> void:
	chapters.clear()
	_by_id.clear()
	if not FileAccess.file_exists(PATH):
		push_warning("StoryDirector: нет %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("StoryDirector: %s — ожидался массив глав" % PATH)
		return
	for entry: Variant in parsed as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var chapter := entry as Dictionary
		chapters.append(chapter)
		_by_id[StringName(chapter.get("id", ""))] = chapter


func current_chapter() -> Dictionary:
	return _by_id.get(StringName(GameState.story.get("chapter", "")), {})


func chapter_title() -> String:
	return String(current_chapter().get("title", ""))


func start_chapter(id: StringName) -> void:
	if not _by_id.has(id):
		push_warning("StoryDirector: нет главы '%s'" % id)
		return
	GameState.story["chapter"] = String(id)
	EventBus.chapter_started.emit(id)
	var chapter := _by_id[id]
	Effects.apply(chapter.get("on_start"), _context)
	evaluate()


func done_beats() -> Array:
	return GameState.story.get("done_beats", [])


func _mark_done(beat_id: String) -> void:
	var done: Array = done_beats()
	if not done.has(beat_id):
		done.append(beat_id)
		GameState.story["done_beats"] = done


## Проверяет все биты текущей главы и выполняет те, чьи условия сошлись.
## Повторяет проход, пока что-то срабатывает: один бит может открыть другой.
func evaluate() -> void:
	var chapter := current_chapter()
	if chapter.is_empty():
		return
	for _pass: int in 8:
		var fired := false
		for entry: Variant in chapter.get("beats", []):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var beat := entry as Dictionary
			var beat_id := String(beat.get("id", ""))
			if done_beats().has(beat_id):
				continue
			if not Condition.evaluate(beat.get("when"), _context):
				continue
			_mark_done(beat_id)
			GameState.story["beat"] = beat_id
			EventBus.beat_reached.emit(StringName(beat_id))
			Effects.apply(beat.get("then"), _context)
			fired = true
		if not fired:
			break
	_check_chapter_end(chapter)


func _check_chapter_end(chapter: Dictionary) -> void:
	var next_id := String(chapter.get("next", ""))
	if next_id == "":
		return
	if not Condition.evaluate(chapter.get("complete_when"), _context):
		return
	start_chapter(StringName(next_id))


func _on_settlement_entered(settlement_id: StringName) -> void:
	_context["settlement"] = String(settlement_id)
	evaluate()


func _on_settlement_exited(_settlement_id: StringName) -> void:
	_context.erase("settlement")


func _on_contract_completed(_id: StringName, _payout: float, _on_time: bool) -> void:
	evaluate()


func _on_hour_passed(_day: int, _hour: float) -> void:
	evaluate()


## Строка для журнала: что игрок должен делать сейчас.
func objective() -> String:
	var chapter := current_chapter()
	if chapter.is_empty():
		return ""
	for entry: Variant in chapter.get("beats", []):
		var beat := entry as Dictionary
		if done_beats().has(String(beat.get("id", ""))):
			continue
		var hint := String(beat.get("objective", ""))
		if hint != "":
			return hint
	return String(chapter.get("objective", ""))
