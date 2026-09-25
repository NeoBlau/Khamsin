extends TestCase
## Находки.
##
## Десять мест, где стоит что-то, чего там быть не должно. Проверяется не
## юмор, а механика: находка засчитывается один раз, ночная — только ночью,
## и все они стоят внутри карты, а не за её краем, куда не доехать.

var eggs: EasterEggs


func before_each() -> void:
	Catalog.ensure_loaded()
	GameState.new_game(20260907)
	eggs = EasterEggs.new()
	host.add_child(eggs)


func after_each() -> void:
	if eggs != null and is_instance_valid(eggs):
		eggs.queue_free()
	eggs = null


func test_all_finds_load() -> void:
	check(eggs.all().size() >= 8, "находок в данных: %d" % eggs.all().size())
	var seen: Array[String] = []
	for entry: Dictionary in eggs.all():
		var id := String(entry["id"])
		check(not seen.has(id), "идентификатор не повторяется: %s" % id)
		seen.append(id)
		check(String(entry.get("note", "")).length() > 20, "%s: есть что показать игроку" % id)
		check(String(entry.get("journal", "")).length() > 10, "%s: есть запись в журнал" % id)
		check(String(entry.get("prop", "")) != "", "%s: задан предмет" % id)


func test_every_find_stands_inside_the_map() -> void:
	var half := Config.world_size() * 0.5
	for entry: Dictionary in eggs.all():
		var at: Array = entry["at"]
		var spot := Vector2(float(at[0]), float(at[1]))
		check(absf(spot.x) < half and absf(spot.y) < half,
			"%s внутри карты: %s" % [entry["id"], spot])
		check(float(entry.get("radius", 0.0)) > 5.0, "%s: радиус находки осмысленный" % entry["id"])


## Находки не должны стоять в посёлке: смысл в том, чтобы свернуть с маршрута.
func test_finds_are_away_from_settlements() -> void:
	if not World.is_built_for(20260907):
		Rng.set_world_seed(20260907)
		World.build_now(20260907)
	for entry: Dictionary in eggs.all():
		var at: Array = entry["at"]
		var spot := Vector2(float(at[0]), float(at[1]))
		for settlement: Settlement in World.settlements:
			var distance := settlement.position.distance_to(spot)
			check(distance > settlement.radius,
				"%s не в посёлке %s: %.0f м при радиусе %.0f"
					% [entry["id"], settlement.id, distance, settlement.radius])


func test_every_find_has_geometry() -> void:
	for entry: Dictionary in eggs.all():
		var node := EasterEggProps.build(StringName(entry["prop"]), 7)
		if not check(node != null, "%s: предмет собирается" % entry["id"]):
			continue
		check(node.get_child_count() > 0, "%s: предмет не пустой" % entry["id"])
		node.free()
	check(EasterEggProps.build(&"выдумка", 1) == null, "неизвестный предмет не собирается")


func test_a_find_counts_once() -> void:
	var entry: Dictionary = eggs.all()[0]
	var id := StringName(entry["id"])
	check(not EasterEggs.is_found(id), "сначала не найдено")
	eggs._discover(id, entry)
	check(EasterEggs.is_found(id), "теперь найдено")
	var notes: Array = GameState.flag(&"found_notes", [])
	check_equal(notes.size(), 1, "запись в журнале одна")
	eggs._discover(id, entry)
	notes = GameState.flag(&"found_notes", [])
	check_equal(notes.size(), 1, "повторно не записывается")


## Каменный круг днём — просто камни. Сообщать о нём днём значит испортить
## находку: весь смысл в том, что ночью он гудит.
func test_night_finds_wait_for_night() -> void:
	var night_entry: Dictionary = {}
	for entry: Dictionary in eggs.all():
		if bool(entry.get("night_only", false)):
			night_entry = entry
	if not check(not night_entry.is_empty(), "ночная находка в данных есть"):
		return
	var id := StringName(night_entry["id"])
	GameState.time_of_day = 13.0
	eggs._discover(id, night_entry)
	check(not EasterEggs.is_found(id), "днём не засчитывается")
	GameState.time_of_day = 1.0
	eggs._discover(id, night_entry)
	check(EasterEggs.is_found(id), "ночью засчитывается")


func test_finds_survive_a_save() -> void:
	var entry: Dictionary = eggs.all()[1]
	eggs._discover(StringName(entry["id"]), entry)
	var snapshot := GameState.serialize()
	GameState.new_game(20260907)
	check(not EasterEggs.is_found(StringName(entry["id"])), "в новой игре не найдено")
	GameState.deserialize(snapshot)
	check(EasterEggs.is_found(StringName(entry["id"])), "после загрузки найдено")
