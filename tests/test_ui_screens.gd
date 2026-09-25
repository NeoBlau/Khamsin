extends TestCase
## Дымовой тест интерфейса.
##
## Экраны собираются кодом, и ошибка в них — это не красный текст в консоли, а
## пустое окно или падение при открытии. Здесь каждый экран открывается,
## проверяется, что он что-то нарисовал, и закрывается. Тест не смотрит, красиво
## ли получилось, — он ловит то, что вообще не открылось.

const SEED := 20260907

var _vehicle: VehicleBody


func before_each() -> void:
	if not World.is_built_for(SEED):
		Rng.set_world_seed(SEED)
		World.build_now(SEED)
	GameState.new_game(SEED)
	# Экранам посёлка и карты нужна машина игрока.
	_vehicle = VehicleBody.new()
	_vehicle.config_id = &"tabuk_6t"
	_vehicle.player_controlled = false
	_vehicle.add_to_group(&"player_vehicle")
	host.add_child(_vehicle)
	_vehicle.global_position = World.settlement(&"mahatta").world_position()


func after_each() -> void:
	SceneRouter.close_all()
	if _vehicle != null and is_instance_valid(_vehicle):
		_vehicle.queue_free()
	_vehicle = null


func _open(screen: StringName, payload: Dictionary = {}) -> Control:
	SceneRouter.open(screen, payload)
	await tree().process_frame
	var node := SceneRouter.get_node_or_null(NodePath("Overlays/%s" % screen))
	return node as Control


## Считает узлы, которые действительно что-то показывают.
func _visible_widgets(root: Node) -> int:
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child: Node in node.get_children():
			pending.append(child)
		if node is Label and not (node as Label).text.is_empty():
			count += 1
		elif node is Button and not (node as Button).text.is_empty():
			count += 1
	return count


func test_every_registered_screen_opens() -> void:
	for screen: StringName in SceneRouter.SCREENS.keys():
		var payload := {}
		if screen == &"dialogue":
			payload = {"dialogue": "intro_dispatcher"}
		elif screen == &"contracts" or screen == &"garage":
			payload = {"settlement": "mahatta"}
		var node := await _open(screen, payload)
		if not check(node != null, "экран '%s' должен открыться" % screen):
			continue
		check_greater(
			float(_visible_widgets(node)), 3.0, "экран '%s' должен что-то показать" % screen
		)
		SceneRouter.close(screen)
		await tree().process_frame
		check(
			SceneRouter.get_node_or_null(NodePath("Overlays/%s" % screen)) == null,
			"экран '%s' должен закрываться" % screen
		)


func test_settlement_screen_lists_offers_and_services() -> void:
	var node := await _open(&"contracts", {"settlement": "mahatta"})
	check(node != null, "экран посёлка должен открыться")
	var text := _collect_text(node)
	check(text.contains("Махатта"), "в заголовке должно быть название посёлка")
	check(text.contains("Заказы"), "должна быть вкладка заказов")
	check(text.contains("Гараж"), "и вкладка гаража")
	check(text.contains("дх"), "и цены в дирхамах")


func test_journal_shows_the_current_chapter() -> void:
	var director := StoryDirector.new()
	director.add_to_group(&"story_director")
	host.add_child(director)
	await tree().process_frame

	var node := await _open(&"journal")
	var text := _collect_text(node)
	check(text.contains("Наследство"), "журнал должен показывать текущую главу")
	check(text.contains("Гильдия"), "и отношения с фракциями")
	director.queue_free()


func test_main_menu_builds() -> void:
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	host.add_child(menu)
	await tree().process_frame
	var text := _collect_text(menu)
	check(text.contains("ХАМСИН"), "в меню должно быть название")
	check(text.contains("Новый рейс"), "и кнопка новой игры")
	check(text.contains("Сид мира"), "и поле ввода сида")
	menu.queue_free()


func test_map_screen_survives_an_unexplored_world() -> void:
	# На старте известны три посёлка из девяти. Карта не должна падать на том,
	# чего игрок ещё не видел.
	GameState.known_settlements.clear()
	var node := await _open(&"map")
	check(node != null, "карта должна открываться даже когда ничего не известно")
	check(_collect_text(node).contains("Известно посёлков: 0"), "и честно об этом писать")


func _collect_text(root: Node) -> String:
	var parts := PackedStringArray()
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child: Node in node.get_children():
			pending.append(child)
		if node is Label:
			parts.append((node as Label).text)
		elif node is Button:
			parts.append((node as Button).text)
		elif node is TabContainer:
			var tabs := node as TabContainer
			for i: int in tabs.get_tab_count():
				parts.append(tabs.get_tab_title(i))
	return "\n".join(parts)


## Ни одна клавиша не должна делать двух дел сразу.
##
## Проверка появилась после настоящей поломки: добавленные скобки для
## переключения радиостанций сели на те же клавиши, что и давление в шинах, а
## выход из машины — на клавишу блокировок. Нажатие делало и то, и другое, и
## заметить это можно было только случайно.
func test_no_key_does_two_things_at_once() -> void:
	# Пары, которые делят клавишу намеренно: в машине и пешком работают разные
	# наборы действий, и пересечение между ними безвредно.
	var allowed := [
		[&"handbrake", &"jump"],
		[&"clutch", &"sprint"],
	]
	var by_key: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if not (event is InputEventKey):
				continue
			var code: int = (event as InputEventKey).physical_keycode
			if code == 0:
				continue
			if not by_key.has(code):
				by_key[code] = [] as Array[StringName]
			(by_key[code] as Array).append(action)

	var collisions := 0
	for code: int in by_key:
		var actions: Array = by_key[code]
		if actions.size() < 2:
			continue
		var excused := false
		for pair: Array in allowed:
			if actions.size() == 2 and actions.has(pair[0]) and actions.has(pair[1]):
				excused = true
		if excused:
			continue
		collisions += 1
		fail("клавиша %s назначена на %s" % [OS.get_keycode_string(code), actions])
	check_equal(collisions, 0, "клавиш с двойным назначением")


## Действия, на которые код ссылается, обязаны существовать в карте ввода:
## обращение к несуществующему действию — это ошибка на каждом кадре.
func test_every_action_the_code_uses_exists() -> void:
	var used: Array[StringName] = [
		&"steer_left", &"steer_right", &"throttle", &"brake", &"handbrake", &"clutch",
		&"shift_up", &"shift_down", &"toggle_4wd", &"toggle_diff_lock", &"toggle_low_range",
		&"pressure_up", &"pressure_down", &"headlights", &"horn", &"camera_cycle",
		&"interact", &"open_map", &"open_journal", &"recover", &"pause", &"free_look",
		&"radio_toggle", &"radio_next", &"radio_prev", &"exit_vehicle", &"sprint", &"jump",
	]
	for action: StringName in used:
		check(InputMap.has_action(action), "действие есть в карте ввода: %s" % action)
