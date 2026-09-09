extends TestCase
## Сюжет: условия, последствия, диалоги, главы.
##
## Содержание сюжета живёт в JSON, а не в коде, поэтому тесты проверяют две
## вещи: что движок делает то, что написано в данных, и что сами данные
## связны — нет ссылок на несуществующие узлы, реплики и посёлки.

const SEED := 20260907

var director: StoryDirector


func before_each() -> void:
	if not World.is_ready or Rng.world_seed != SEED:
		Rng.set_world_seed(SEED)
		World.build_now(SEED)
	GameState.new_game(SEED)
	Dialogue.reload()


func after_each() -> void:
	if director != null and is_instance_valid(director):
		director.queue_free()
	director = null


func _director() -> StoryDirector:
	director = StoryDirector.new()
	host.add_child(director)
	return director


# --- Условия ---------------------------------------------------------------

func test_empty_condition_is_true() -> void:
	check(Condition.evaluate(null), "пустое условие должно выполняться")
	check(Condition.evaluate({}), "пустой объект тоже")


func test_flag_conditions() -> void:
	check(not Condition.evaluate({"flag": "nope"}), "невзведённый флаг ложен")
	GameState.set_flag(&"nope", true)
	check(Condition.evaluate({"flag": "nope"}), "взведённый флаг истинен")
	check(not Condition.evaluate({"not_flag": "nope"}), "not_flag — обратное")


func test_money_and_day_conditions() -> void:
	GameState.money = 1000.0
	check(Condition.evaluate({"money_at_least": 1000}), "ровно столько — уже хватает")
	check(not Condition.evaluate({"money_at_least": 1001}), "на рубль больше — уже нет")
	check(Condition.evaluate({"money_below": 1001}), "money_below")
	GameState.day = 5
	check(Condition.evaluate({"day_at_least": 5}), "день")


func test_composite_conditions() -> void:
	GameState.money = 500.0
	GameState.set_flag(&"a", true)
	check(
		Condition.evaluate({"all": [{"flag": "a"}, {"money_at_least": 100}]}),
		"all: оба выполнены"
	)
	check(
		not Condition.evaluate({"all": [{"flag": "a"}, {"money_at_least": 9000}]}),
		"all: одно не выполнено"
	)
	check(
		Condition.evaluate({"any": [{"flag": "b"}, {"money_at_least": 100}]}),
		"any: хотя бы одно"
	)
	check(Condition.evaluate({"not": {"flag": "b"}}), "not")


func test_unknown_condition_key_is_false_and_loud() -> void:
	check(not Condition.evaluate({"выдумка": 1}), "неизвестный ключ не должен молча срабатывать")


# --- Последствия -----------------------------------------------------------

func test_effects_change_the_world() -> void:
	var before := GameState.money
	Effects.apply({"money": 250, "set_flag": "paid", "reputation": {"faction": "guild", "amount": 5}})
	check_near(GameState.money, before + 250.0, 0.01, "деньги")
	check(bool(GameState.flag(&"paid")), "флаг")
	check_near(GameState.reputation_of(&"guild"), 5.0, 0.01, "репутация")


func test_effects_can_put_a_story_contract_on_the_board() -> void:
	Effects.apply({
		"offer_contract": {
			"id": "test_story", "cargo": "unmarked_crate", "units": 1,
			"from": "bir_saqr", "to": "nuqta_7", "payout": 1500, "hours": 20,
		}
	})
	var offers := ContractBoard.offers(World.settlement(&"bir_saqr"))
	var found: Contract = null
	for contract: Contract in offers:
		if contract.id == &"test_story":
			found = contract
	check(found != null, "сюжетный заказ должен появиться на доске нужного посёлка")
	if found != null:
		check_equal(found.destination_id, &"nuqta_7", "адрес доставки")
		check_greater(found.route_length, 100.0, "длина маршрута должна посчитаться")
		check(offers[0].id == &"test_story", "сюжетный заказ идёт первым в списке")


# --- Диалоги ---------------------------------------------------------------

func test_dialogue_walks_the_graph() -> void:
	var dialogue := Dialogue.open(&"intro_dispatcher")
	check(dialogue != null, "разговор должен открыться")
	check_equal(dialogue.speaker(), "Диспетчер Надия", "имя говорящего")
	check(not dialogue.text().is_empty(), "у реплики должен быть текст")
	check(dialogue.choices().is_empty(), "у первой реплики выбора нет")
	dialogue.advance()
	check(not dialogue.is_finished(), "разговор продолжается")
	check_greater(float(dialogue.choices().size()), 1.0, "во второй реплике есть выбор")

	var guard := 0
	while not dialogue.is_finished() and guard < 32:
		dialogue.advance(0)
		guard += 1
	check(dialogue.is_finished(), "разговор должен закончиться, а не зациклиться")
	check(bool(GameState.flag(&"met_dispatcher")), "выбранная ветка должна оставить след")


func test_dialogue_choice_effects_apply() -> void:
	GameState.money = 20000.0
	var dialogue := Dialogue.open(&"pay_first_instalment")
	var options := dialogue.choices()
	check_equal(options.size(), 2, "при деньгах доступны оба ответа")
	dialogue.advance(0)
	check(bool(GameState.flag(&"debt_first_paid")), "оплата должна закрыть долг")
	check_near(GameState.money, 14000.0, 0.01, "и списать шесть тысяч")


func test_dialogue_hides_unavailable_choices() -> void:
	GameState.money = 100.0
	var dialogue := Dialogue.open(&"pay_first_instalment")
	check_equal(dialogue.choices().size(), 1, "без денег вариант оплаты показывать незачем")


func test_all_dialogue_links_resolve() -> void:
	# Ссылка на несуществующий узел — это тупик посреди разговора. Глазами в
	# JSON такое не ловится, а тестом ловится за секунду.
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(Dialogue.PATH))
	check(typeof(raw) == TYPE_DICTIONARY, "файл диалогов должен быть объектом")
	for dialogue_id: String in (raw as Dictionary).keys():
		var graph: Dictionary = (raw as Dictionary)[dialogue_id]
		var nodes: Dictionary = graph.get("nodes", {})
		check(nodes.has(String(graph.get("start", "start"))), "%s: нет стартового узла" % dialogue_id)
		for node_id: String in nodes.keys():
			var node: Dictionary = nodes[node_id]
			var next := String(node.get("next", ""))
			if next != "":
				check(nodes.has(next), "%s.%s: next ведёт в никуда ('%s')" % [dialogue_id, node_id, next])
			for choice: Variant in node.get("choices", []):
				var goto := String((choice as Dictionary).get("goto", ""))
				if goto != "":
					check(
						nodes.has(goto),
						"%s.%s: выбор ведёт в никуда ('%s')" % [dialogue_id, node_id, goto]
					)
			if next == "" and node.get("choices", []).is_empty():
				check(true, "%s.%s — концовка" % [dialogue_id, node_id])


# --- Главы -----------------------------------------------------------------

func test_first_chapter_starts_automatically() -> void:
	var story := _director()
	check_equal(String(GameState.story["chapter"]), "inheritance", "должна начаться первая глава")
	check(not story.chapter_title().is_empty(), "у главы есть название")
	check(not story.objective().is_empty(), "и текущая задача для журнала")


func test_beat_fires_when_its_condition_is_met() -> void:
	var story := _director()
	check(not story.done_beats().has("intro"), "до приезда в город бит не срабатывает")
	EventBus.settlement_entered.emit(&"mahatta")
	check(story.done_beats().has("intro"), "приезд в Махатту должен запустить вступление")


func test_beats_do_not_repeat() -> void:
	var story := _director()
	EventBus.settlement_entered.emit(&"mahatta")
	var count := story.done_beats().size()
	EventBus.settlement_entered.emit(&"mahatta")
	EventBus.settlement_entered.emit(&"mahatta")
	check_equal(story.done_beats().size(), count, "повторный приезд не должен повторять сюжет")


func test_chapter_advances_when_complete() -> void:
	var story := _director()
	GameState.set_flag(&"debt_first_paid", true)
	story.evaluate()
	check_equal(String(GameState.story["chapter"]), "the_crate", "после долга начинается вторая глава")


func test_chapter_data_is_consistent() -> void:
	var story := _director()
	var known: Array[String] = []
	for settlement: Settlement in World.settlements:
		known.append(String(settlement.id))
	for chapter: Dictionary in story.chapters:
		var next := String(chapter.get("next", ""))
		if next != "":
			var found := false
			for other: Dictionary in story.chapters:
				if String(other.get("id", "")) == next:
					found = true
			check(found, "глава %s ссылается на несуществующую '%s'" % [chapter.get("id"), next])
		for entry: Variant in chapter.get("beats", []):
			var beat := entry as Dictionary
			var dialogue_id := String((beat.get("then", {}) as Dictionary).get("dialogue", ""))
			if dialogue_id != "":
				check(
					Dialogue.exists(StringName(dialogue_id)),
					"бит %s зовёт несуществующий разговор '%s'" % [beat.get("id"), dialogue_id]
				)
			var settlement := String((beat.get("when", {}) as Dictionary).get("settlement", ""))
			if settlement != "":
				check(known.has(settlement), "бит %s ждёт неизвестный посёлок '%s'" % [beat.get("id"), settlement])
