class_name SettlementManager
extends Node3D
## Подгрузка посёлков.
##
## Посёлок — это сотни панелей: дома, комнаты внутри, заправка, пальмы. Оазис
## Дяди Вали — почти тысяча двести мешей. Собранный за один кадр, он даёт
## просадку почти на двести миллисекунд ровно в тот момент, когда в него
## въезжаешь, — то есть одиннадцать пропущенных кадров на скорости.
##
## Поэтому сборка идёт очередью шагов с бюджетом на кадр. Радиус подобран так,
## чтобы посёлок успевал собраться раньше, чем станет виден.

const BUILD_RADIUS := 900.0
const DROP_RADIUS := 1300.0
## Сколько посёлков держим собранными одновременно.
const MAX_LIVE := 2
## Бюджет сборки на кадр, миллисекунды. Четыре — это четверть кадра на
## шестидесяти герцах: незаметно даже на слабой машине.
const FRAME_BUDGET_MS := 4.0

var target: Node3D

var _live: Dictionary = {}
var _doors: Dictionary = {}
var _lights: Dictionary = {}
var _queues: Dictionary = {}
var _poll: float = 0.0
var _night: bool = false


func begin(follow: Node3D) -> void:
	target = follow
	set_process(true)
	_refresh()


func _process(delta: float) -> void:
	_advance_queues()
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.9
	_refresh()
	_update_lamps()


## Доводит начатые посёлки, пока не кончится бюджет кадра.
func _advance_queues() -> void:
	if _queues.is_empty():
		return
	var began := Time.get_ticks_usec()
	for id: StringName in _queues.keys():
		var steps: Array = _queues[id]
		while not steps.is_empty():
			var step: Callable = steps.pop_front()
			step.call()
			if float(Time.get_ticks_usec() - began) / 1000.0 >= FRAME_BUDGET_MS:
				if steps.is_empty():
					_queues.erase(id)
				return
		_queues.erase(id)


func _refresh() -> void:
	if target == null or not is_instance_valid(target):
		return
	var here := target.global_position
	var ranked: Array[Settlement] = []
	for settlement: Settlement in World.settlements:
		if settlement.world_position().distance_to(here) < BUILD_RADIUS:
			ranked.append(settlement)
	ranked.sort_custom(func(a: Settlement, b: Settlement) -> bool:
		return a.world_position().distance_to(here) < b.world_position().distance_to(here)
	)
	for i: int in ranked.size():
		if i >= MAX_LIVE:
			break
		if not _live.has(ranked[i].id):
			_start(ranked[i])
	for id: StringName in _live.keys():
		var settlement := World.settlement(id)
		if settlement == null:
			continue
		if settlement.world_position().distance_to(here) > DROP_RADIUS:
			_drop(id)


func _start(settlement: Settlement) -> void:
	var plan := SettlementBuilder.plan(settlement)
	var root: Node3D = plan["root"]
	add_child(root)
	_live[settlement.id] = root
	_doors[settlement.id] = plan["doors"]
	_lights[settlement.id] = plan["lights"]
	_queues[settlement.id] = plan["steps"]


func _drop(id: StringName) -> void:
	var root: Node3D = _live.get(id)
	if root != null and is_instance_valid(root):
		root.queue_free()
	_live.erase(id)
	_doors.erase(id)
	_lights.erase(id)
	_queues.erase(id)


## Готов ли посёлок целиком. Нужно тестам и тем, кто ждёт, пока он достроится.
func is_complete(id: StringName) -> bool:
	return _live.has(id) and not _queues.has(id)


## Достраивает всё начатое без оглядки на бюджет. Нужно инструментам и тестам,
## где кадры не идут и ждать нечего.
func finish_all() -> void:
	for id: StringName in _queues.keys():
		for step: Callable in _queues[id]:
			step.call()
	_queues.clear()


## Фонари горят ночью и в бурю. Днём они не просто не нужны — они портят
## картинку, добавляя засветку там, где солнце и так всё выжигает.
func _update_lamps() -> void:
	var want := GameState.is_night()
	if want == _night:
		return
	_night = want
	for id: StringName in _lights:
		for lamp: Node3D in _lights[id]:
			if is_instance_valid(lamp):
				lamp.visible = want


## Входы в здания рядом с точкой. По ним работает взаимодействие пешком.
func doors_near(point: Vector3, radius: float = 4.5) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in _doors:
		var origin: Vector3 = (_live[id] as Node3D).global_position
		for door: Dictionary in _doors[id]:
			var at: Vector3 = origin + (door["at"] as Vector3)
			if at.distance_to(point) <= radius:
				var entry := door.duplicate()
				entry["world"] = at
				entry["settlement"] = id
				out.append(entry)
	return out


func live_count() -> int:
	return _live.size()


func is_built(id: StringName) -> bool:
	return _live.has(id)
