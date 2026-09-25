extends Node
## Геймпад целиком принадлежит этому узлу, и на то есть причина.
##
## Действий в игре больше, чем кнопок на геймпаде: двадцать против четырнадцати
## (GUIDE не трогаем, он системный). Разложить всё по одному нажатию нельзя —
## что-то пришлось бы выкинуть, а выкидывать нечего: блокировка дифференциала и
## давление в шинах в пустыне нужны не реже фар.
##
## Поэтому BACK работает модификатором: сам по себе он не делает ничего, а с
## ним лицевые кнопки и крестовина дают второй слой. Получается двадцать два
## действия на четырнадцати кнопках без единого совпадения.
##
## Почему раскладка живёт в коде, а не в InputMap: слой в InputMap не выразить.
## Godot не умеет аккордов, и если оставить кнопке базовую привязку в карте
## ввода, то BACK+A дёрнет ручник заодно с блокировкой — состояние действия
## обновляется до того, как узел успеет что-то отменить. Так что привязок
## InputEventJoypadButton в project.godot нет вовсе: стики и курки остаются в
## карте (у них слоя нет и быть не может), а кнопки синтезирует этот узел.

## Кнопка-модификатор. Базового действия у неё нет намеренно.
const MODIFIER := JOY_BUTTON_BACK

## Первый слой — то, что нужно под пальцем сразу.
const BASE: Dictionary = {
	JOY_BUTTON_A: [&"handbrake", &"jump"],
	JOY_BUTTON_B: [&"interact"],
	JOY_BUTTON_X: [&"clutch"],
	JOY_BUTTON_Y: [&"exit_vehicle"],
	JOY_BUTTON_START: [&"pause"],
	JOY_BUTTON_LEFT_STICK: [&"toggle_4wd", &"sprint"],
	JOY_BUTTON_RIGHT_STICK: [&"camera_cycle"],
	JOY_BUTTON_LEFT_SHOULDER: [&"shift_down"],
	JOY_BUTTON_RIGHT_SHOULDER: [&"shift_up"],
	JOY_BUTTON_DPAD_UP: [&"horn"],
	JOY_BUTTON_DPAD_DOWN: [&"toggle_low_range"],
	JOY_BUTTON_DPAD_LEFT: [&"pressure_down"],
	JOY_BUTTON_DPAD_RIGHT: [&"pressure_up"],
}

## Второй слой — то, что нажимают раз в поездку, а не раз в секунду.
const LAYER: Dictionary = {
	JOY_BUTTON_A: [&"toggle_diff_lock"],
	JOY_BUTTON_B: [&"radio_toggle"],
	JOY_BUTTON_X: [&"headlights"],
	JOY_BUTTON_Y: [&"open_journal"],
	JOY_BUTTON_DPAD_UP: [&"open_map"],
	JOY_BUTTON_DPAD_DOWN: [&"recover"],
	JOY_BUTTON_DPAD_LEFT: [&"radio_prev"],
	JOY_BUTTON_DPAD_RIGHT: [&"radio_next"],
}

## Пары действий, которым совпадать на одной кнопке разрешено: они никогда не
## слушаются одновременно. Ручник читает машина, прыжок — пешеход; пока герой
## за рулём, прыгать некому, и наоборот.
const EXCLUSIVE: Array = [
	[&"handbrake", &"jump"],
	[&"toggle_4wd", &"sprint"],
]

## Мёртвая зона правого стика. Ниже — камера стоит.
const LOOK_DEADZONE := 0.18
## Пикселей «мыши» в секунду при полном отклонении. Подобрано так, чтобы полный
## разворот головы в кабине занимал примерно секунду.
const LOOK_SPEED := 620.0

var enabled: bool = true

## Кнопка -> действия, которые она сейчас держит. Слой выбирается в момент
## нажатия и запоминается: если нажать A, потом взяться за BACK, а потом
## отпустить A, отпустить нужно ручник, а не блокировку.
var _down: Dictionary = {}
var _look_active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


static func actions_for(button: int, modifier: bool) -> Array:
	if modifier:
		# Слой глухой там, где ему нечего делать: BACK+START не должен ставить
		# игру на паузу, иначе модификатор превращается в лотерею.
		return (LAYER.get(button, []) as Array).duplicate()
	return (BASE.get(button, []) as Array).duplicate()


## Сердце узла и единственное место, где меняется состояние. Чистое в том
## смысле, что зависит только от аргументов и собственных полей: тестам не
## нужен ни геймпад, ни дерево сцены.
func plan(pressed: Dictionary, modifier: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for button: int in _down.keys():
		if not bool(pressed.get(button, false)):
			for action: StringName in _down[button] as Array:
				out.append({&"action": action, &"pressed": false})
			_down.erase(button)
	for button: Variant in pressed.keys():
		var index := int(button)
		if not bool(pressed[button]) or _down.has(index):
			continue
		var actions := actions_for(index, modifier)
		if actions.is_empty():
			continue
		_down[index] = actions
		for action: StringName in actions:
			out.append({&"action": action, &"pressed": true})
	return out


func _process(_delta: float) -> void:
	if not enabled or Input.get_connected_joypads().is_empty():
		return
	var modifier := _any_pad_button(MODIFIER)
	var pressed: Dictionary = {}
	for button: Variant in BASE.keys():
		pressed[int(button)] = _any_pad_button(int(button))
	for button: Variant in LAYER.keys():
		pressed[int(button)] = _any_pad_button(int(button))
	for change: Dictionary in plan(pressed, modifier):
		var event := InputEventAction.new()
		event.action = change[&"action"] as StringName
		event.pressed = bool(change[&"pressed"])
		event.strength = 1.0 if event.pressed else 0.0
		Input.parse_input_event(event)
	_update_look(_delta)


## Правый стик крутит голову. Отдельного действия под это нет: камера и пешеход
## уже умеют слушать мышь, так что стик прикидывается мышью — одна ветка кода
## вместо двух, и настройка чувствительности работает та же.
func _update_look(delta: float) -> void:
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	var moved := stick.length() > LOOK_DEADZONE
	if moved != _look_active:
		_look_active = moved
		var event := InputEventAction.new()
		event.action = &"free_look"
		event.pressed = moved
		event.strength = 1.0 if moved else 0.0
		Input.parse_input_event(event)
	if not moved:
		return
	var motion := InputEventMouseMotion.new()
	motion.relative = look_delta(stick, delta)
	motion.screen_relative = motion.relative
	Input.parse_input_event(motion)


## Квадратичная характеристика: у центра стик точный, у края быстрый.
static func look_delta(stick: Vector2, delta: float) -> Vector2:
	var magnitude := stick.length()
	if magnitude <= LOOK_DEADZONE:
		return Vector2.ZERO
	var scaled := (magnitude - LOOK_DEADZONE) / (1.0 - LOOK_DEADZONE)
	return stick.normalized() * (scaled * scaled * LOOK_SPEED * delta)


func _any_pad_button(button: int) -> bool:
	for device: int in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device, button):
			return true
	return false
