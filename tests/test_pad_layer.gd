extends TestCase
## Раскладка геймпада. Проверяем ровно то, что руками не проверишь: что ни одна
## кнопка не делает двух вещей сразу и что слой не залипает.

const PadLayer := preload("res://src/core/pad_layer.gd")


func _pad() -> Node:
	var pad: Node = PadLayer.new()
	pad.set_process(false)
	return pad


## Главная проверка. Кнопок меньше, чем действий, и соблазн повесить второе
## назначение «пока сойдёт» велик — от него и страхуемся.
func test_no_pad_button_does_two_things_at_once() -> void:
	var collisions := 0
	for layer: Dictionary in [PadLayer.BASE, PadLayer.LAYER]:
		for button: Variant in layer.keys():
			var actions: Array = layer[button]
			if actions.size() < 2:
				continue
			var excused := false
			for pair: Array in PadLayer.EXCLUSIVE:
				if actions.size() == 2 and actions.has(pair[0]) and actions.has(pair[1]):
					excused = true
			if not excused:
				collisions += 1
				fail("кнопка %d назначена на %s" % [int(button), actions])
	check_equal(collisions, 0, "кнопок с двойным назначением")


## Модификатор не имеет базового действия — иначе нажать его, не дёрнув ничего
## лишнего, было бы нельзя.
func test_modifier_has_no_action_of_its_own() -> void:
	check(not (PadLayer.BASE.has(PadLayer.MODIFIER)), "у BACK нет базового действия")
	check(not (PadLayer.LAYER.has(PadLayer.MODIFIER)), "у BACK нет действия в слое")


## Каждое действие раскладки существует в карте ввода: опечатка в StringName
## иначе молча превращает кнопку в пустышку.
func test_every_mapped_action_exists() -> void:
	var missing := 0
	for layer: Dictionary in [PadLayer.BASE, PadLayer.LAYER]:
		for button: Variant in layer.keys():
			for action: StringName in layer[button] as Array:
				if not InputMap.has_action(action):
					missing += 1
					fail("действия %s нет в карте ввода" % action)
	check_equal(missing, 0, "несуществующих действий")


## Кнопки геймпада в project.godot остаться не должны: раскладкой владеет узел,
## и вторая копия привязок неизбежно разойдётся с первой.
func test_input_map_has_no_pad_buttons() -> void:
	var found := 0
	for action: StringName in InputMap.get_actions():
		# Встроенные ui_* оставляем движку: ими ходят по меню, и свои привязки
		# к геймпаду у них были до нас.
		if String(action).begins_with("ui_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:
				found += 1
				fail("в карте ввода осталась кнопка геймпада у %s" % action)
	check_equal(found, 0, "привязок кнопок в карте ввода")
	# А вот оси остаться обязаны: у руля и курков слоя нет.
	check(
		InputMap.action_get_events(&"throttle").any(func(e: InputEvent) -> bool:
			return e is InputEventJoypadMotion),
		"газ остался на курке"
	)


func test_press_and_release_are_symmetric() -> void:
	var pad := _pad()
	var changes: Array = pad.plan({JOY_BUTTON_A: true}, false)
	check_equal(changes.size(), 2, "A нажата: ручник и прыжок")
	check(bool(changes[0][&"pressed"]), "нажатие")
	changes = pad.plan({JOY_BUTTON_A: false}, false)
	check_equal(changes.size(), 2, "A отпущена: оба действия сняты")
	check(not (bool(changes[0][&"pressed"])), "отпускание")
	check_equal(pad.plan({JOY_BUTTON_A: false}, false).size(), 0, "повторов нет")
	pad.free()


func test_modifier_switches_the_layer() -> void:
	var pad := _pad()
	var changes: Array = pad.plan({JOY_BUTTON_A: true}, true)
	check_equal(changes.size(), 1, "BACK+A — одно действие")
	check_equal(changes[0][&"action"], &"toggle_diff_lock", "блокировка дифференциала")
	pad.plan({JOY_BUTTON_A: false}, true)
	changes = pad.plan({JOY_BUTTON_A: true}, false)
	check_equal(changes.size(), 2, "без BACK — снова ручник")
	pad.free()


## Тот самый случай, ради которого слой запоминается в момент нажатия: нажали A
## под ручник, потом взялись за BACK, потом отпустили. Отпустить должно ручник,
## а не блокировку, иначе ручник останется затянутым навсегда.
func test_layer_is_decided_at_press_not_at_release() -> void:
	var pad := _pad()
	pad.plan({JOY_BUTTON_A: true}, false)
	var changes: Array = pad.plan({JOY_BUTTON_A: false}, true)
	var released: Array[StringName] = []
	for change: Dictionary in changes:
		released.append(change[&"action"] as StringName)
	check(released.has(&"handbrake"), "ручник отпущен")
	check(not (released.has(&"toggle_diff_lock")), "блокировка не трогалась")
	pad.free()


## С модификатором кнопка, которой в слое нечего делать, молчит. Иначе BACK
## превращается в лотерею: половина кнопок меняет смысл, половина нет.
func test_layer_is_silent_where_it_has_nothing_to_say() -> void:
	var pad := _pad()
	check_equal(pad.plan({JOY_BUTTON_START: true}, true).size(), 0, "BACK+START молчит")
	check_equal(pad.plan({JOY_BUTTON_START: true}, false).size(), 1, "без BACK — пауза")
	pad.free()


func test_look_stick_has_a_deadzone_and_a_curve() -> void:
	check_equal(PadLayer.look_delta(Vector2(0.1, 0.0), 0.016), Vector2.ZERO, "мёртвая зона")
	var half := PadLayer.look_delta(Vector2(0.6, 0.0), 0.016).x
	var full := PadLayer.look_delta(Vector2(1.0, 0.0), 0.016).x
	check(full > half, "край стика быстрее середины")
	# Квадратичная характеристика: на 60% отклонения — заметно меньше половины.
	check(half < full * 0.5, "у центра стик точнее, чем линейный")
	check(full < 24.0, "полное отклонение — не рывок через весь экран")
