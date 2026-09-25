extends Node3D
## Сцена мира: собирает всё вместе и держит игровой цикл.
##
## Здесь нет ни физики, ни генерации — только сборка и связи. Если этот файл
## начнёт разрастаться, значит что-то поехало: логика должна жить в своих
## модулях, а сцена — знать, кто кого держит и кто кому что передаёт.

signal world_ready()

const SETTLEMENT_POLL := 0.4

@export var spawn_override: NodePath

var vehicle: VehicleBody
var camera: VehicleCamera
var terrain: TerrainManager
var sky: SkyController
var weather: Weather
var story: StoryDirector
var cargo: CargoMonitor
var hud: CanvasLayer
var engine_audio: EngineAudio
var walker: Walker
var on_foot: bool = false
var grime: Grime
var camels: CamelHerd
var places: SettlementManager
var eggs: EasterEggs

var _loading: Control
var _poll_timer: float = 0.0
var _current_settlement: StringName = &""
var is_world_ready: bool = false
var _headlights: Array[SpotLight3D] = []
var _headlights_on: bool = false


func _ready() -> void:
	Catalog.ensure_loaded()
	_show_loading("Собираем мир…")
	if World.is_built_for(_expected_seed()):
		# Отложенно, а не сразу: `_ready` вызывается внутри `add_child`, и
		# сигнал, выпущенный отсюда напрямую, ушёл бы раньше, чем кто-то успел
		# на него подписаться.
		_on_world_built.call_deferred()
	else:
		World.build_finished.connect(_on_world_built, CONNECT_ONE_SHOT)
		World.build_async(_expected_seed())


func _expected_seed() -> int:
	return Rng.world_seed


func _on_world_built() -> void:
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)

	sky = SkyController.new()
	sky.name = "Sky"
	sky.weather = weather
	add_child(sky)

	terrain = TerrainManager.new()
	terrain.name = "Terrain"
	add_child(terrain)

	_spawn_vehicle()

	grime.attach(vehicle, weather)

	camels = CamelHerd.new()
	camels.name = "Camels"
	add_child(camels)
	camels.begin(vehicle)

	places = SettlementManager.new()
	places.name = "Places"
	add_child(places)
	places.begin(vehicle)

	eggs = EasterEggs.new()
	eggs.name = "Finds"
	add_child(eggs)
	eggs.begin(vehicle)

	cargo = CargoMonitor.new()
	cargo.name = "CargoMonitor"
	cargo.weather = weather
	cargo.vehicle = vehicle
	add_child(cargo)

	story = StoryDirector.new()
	story.name = "Story"
	story.add_to_group(&"story_director")
	add_child(story)

	camera = VehicleCamera.new()
	camera.name = "Camera"
	camera.base_fov = Settings.fov
	add_child(camera)
	camera.follow(vehicle)
	# Из кабины видом управляет мышь, значит её надо захватить. Снаружи —
	# нет, и курсор должен вернуться.
	camera.mode_changed.connect(func(_mode: VehicleCamera.Mode) -> void: _update_mouse_mode())

	# Ближнее кольцо строим сразу и синхронно: без земли под колёсами машина
	# успевает улететь в пустоту за те кадры, пока считаются потоки.
	terrain.begin(World.field, vehicle)
	terrain.build_immediate(vehicle.global_position)

	hud = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "Hud"
	hud.add_to_group(&"ui_layer")
	add_child(hud)
	hud.setup(vehicle, weather, story, self)

	walker = Walker.new()
	add_child(walker)
	walker.activate(false)
	walker.wants_to_enter_vehicle.connect(board_vehicle)

	EventBus.dialogue_requested.connect(_on_dialogue_requested)
	SceneRouter.screen_opened.connect(func(_screen: StringName) -> void: _update_mouse_mode())
	SceneRouter.screen_closed.connect(func(_screen: StringName) -> void: _update_mouse_mode())

	_hide_loading()
	is_world_ready = true
	world_ready.emit()
	EventBus.notify("Добро пожаловать в Хамсин")


func _spawn_vehicle() -> void:
	vehicle = VehicleBody.new()
	vehicle.name = "Vehicle"
	vehicle.add_to_group(&"player_vehicle")
	vehicle.config_id = GameState.vehicle_id
	vehicle.player_controlled = true
	vehicle.surface_provider = World.surface_at
	add_child(vehicle)

	var visuals := ChassisBuilder.build(vehicle.config)
	var wheel_nodes: Array[Node3D] = visuals["wheels"]
	for node: Node3D in wheel_nodes:
		vehicle.add_child(node)
	vehicle.attach_visuals(visuals["chassis"], wheel_nodes, visuals)
	_headlights = visuals["headlights"]

	engine_audio = EngineAudio.new()
	engine_audio.vehicle = vehicle
	add_child(engine_audio)

	# Грязь живёт на самой машине: она её собственность и уезжает вместе с ней.
	grime = Grime.new()
	vehicle.add_child(grime)

	vehicle.global_transform = _spawn_transform()
	vehicle.refresh_cargo_mass()


func _spawn_transform() -> Transform3D:
	if GameState.has_spawn_transform:
		return GameState.spawn_transform
	var id := GameState.spawn_settlement
	if id == &"" and not World.settlements.is_empty():
		id = World.settlements[0].id
	return World.spawn_transform(id)


func _process(delta: float) -> void:
	if not is_world_ready:
		return

	# Время идёт от реального, но только когда мир не на паузе: стоять в меню
	# биржи полдня — не то приключение, за которым сюда приходят.
	GameState.advance_time(delta / Config.seconds_per_game_hour)

	vehicle.wind_velocity = weather.wind_vector()
	camera.far = sky.draw_distance()

	# Радио слушают из машины: приём считается от её точки, а не от камеры.
	var here := walker.global_position if on_foot else vehicle.global_position
	Audio.radio.listen_from(Vector2(here.x, here.z), GameState.time_of_day)
	Audio.set_wind(clampf(weather.wind_speed / 22.0, 0.0, 1.0), weather.dust)

	_poll_timer += delta
	if _poll_timer >= SETTLEMENT_POLL:
		_poll_timer = 0.0
		_check_settlement()
		_auto_headlights()
		_catch_falls()


## Страховка от провала сквозь мир.
##
## Ландшафт подгружается кусками, и на слабой машине или при телепорте игрок
## может оказаться там, где коллизия ещё не собралась. Падение в пустоту —
## худший из возможных багов: игра не сломана, но играть в неё нельзя.
## Проверка стоит один вызов height() в полсекунды.
func _catch_falls() -> void:
	var ground := World.height(vehicle.global_position.x, vehicle.global_position.z)
	if vehicle.global_position.y > ground - 6.0:
		return
	push_warning("Машина провалилась под ландшафт, возвращаю на поверхность")
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.global_position = Vector3(
		vehicle.global_position.x, ground + 1.5, vehicle.global_position.z
	)


func _unhandled_input(event: InputEvent) -> void:
	if not is_world_ready:
		return
	if event.is_action_pressed(&"headlights"):
		_headlights_on = not _headlights_on
		for light: SpotLight3D in _headlights:
			light.visible = _headlights_on
	elif event.is_action_pressed(&"open_map"):
		EventBus.screen_requested.emit(&"map", {})
	elif event.is_action_pressed(&"open_journal"):
		EventBus.screen_requested.emit(&"journal", {})
	elif event.is_action_pressed(&"interact"):
		_interact()
	elif event.is_action_pressed(&"radio_toggle"):
		Audio.radio.toggle()
		EventBus.notify("Радио %s" % ("включено" if Audio.radio.enabled else "выключено"))
	elif event.is_action_pressed(&"radio_next"):
		Audio.radio.step_station(1)
	elif event.is_action_pressed(&"radio_prev"):
		Audio.radio.step_station(-1)
	elif event.is_action_pressed(&"exit_vehicle") and not on_foot:
		leave_vehicle()


## Фары включаются сами в сумерках и в бурю. Ручной выключатель это не отменяет:
## автоматика только предлагает, игрок решает.
func _auto_headlights() -> void:
	var needed := GameState.is_night() or weather.dust > 0.55
	if needed == _headlights_on:
		return
	_headlights_on = needed
	for light: SpotLight3D in _headlights:
		light.visible = _headlights_on


func _check_settlement() -> void:
	var here := World.settlement_at(vehicle.global_position)
	var id: StringName = here.id if here != null else &""
	if id == _current_settlement:
		return
	if _current_settlement != &"":
		EventBus.settlement_exited.emit(_current_settlement)
	_current_settlement = id
	if id == &"":
		return
	GameState.discover_settlement(id)
	vehicle.sync_to_state()
	EventBus.settlement_entered.emit(id)


# --- Пешком ----------------------------------------------------------------


## Выйти из машины. Только на стоянке: выпрыгивать на ходу — это отдельная
## механика с отдельными последствиями, и в курьерском симуляторе она лишняя.
func leave_vehicle() -> bool:
	if on_foot:
		return false
	# Судим по горизонтальной скорости, а не по полной. Полная включает
	# вертикальную: машина, осевшая на подвеске после прыжка с дюны, стоит на
	# месте, но `speed` у неё несколько метров в секунду, и дверь не
	# открывается без видимой причины.
	var drift := Vector3(vehicle.linear_velocity.x, 0.0, vehicle.linear_velocity.z).length()
	if drift > 1.2:
		EventBus.notify("Сначала остановитесь")
		return false
	on_foot = true
	vehicle.player_controlled = false
	vehicle.input.throttle = 0.0
	vehicle.input.brake = 0.0
	vehicle.input.handbrake = 1.0
	vehicle.sync_to_state()

	walker.place_at(Transform3D(vehicle.global_transform.basis, _door_position()))
	walker.activate(true)
	camera.current = false
	_update_mouse_mode()
	EventBus.notify("Вы вышли из машины. X — сесть обратно, F — взаимодействие")
	return true


## Сесть обратно. Дверь не телепорт: до машины надо дойти.
func board_vehicle() -> bool:
	if not on_foot:
		return false
	var reach := walker.global_position.distance_to(vehicle.global_position)
	if reach > _boarding_distance():
		EventBus.notify("До машины ещё идти")
		return false
	on_foot = false
	walker.activate(false)
	vehicle.player_controlled = true
	vehicle.input.handbrake = 0.0
	camera.current = true
	_update_mouse_mode()
	EventBus.notify("За рулём")
	return true


## Где именно игрок оказывается, выйдя из кабины: у водительской двери, а не
## в центре машины и не под ней.
func _door_position() -> Vector3:
	var xform := vehicle.global_transform
	var size := vehicle.config.body_size
	var beside := xform.basis.x * (-size.x * 0.5 - 0.7)
	var along := -xform.basis.z * (-size.z * 0.5 + size.z * 0.34)
	var spot := xform.origin + beside + along
	return Vector3(spot.x, World.height(spot.x, spot.z) + 0.15, spot.z)


## Радиус посадки считается от габарита машины, а не фиксированным числом:
## у маршрутки и у шеститонника он разный.
func _boarding_distance() -> float:
	var size := vehicle.config.body_size
	return maxf(size.x, size.z) * 0.5 + 2.2


## Мышь захватывается, когда ей управляют видом: пешком и из кабины. Как
## только открыт любой экран — отпускается, иначе по кнопкам не попасть.
func _update_mouse_mode() -> void:
	var wants_capture := (on_foot or camera.mode == VehicleCamera.Mode.COCKPIT) \
		and not SceneRouter.is_overlay_open()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if wants_capture else Input.MOUSE_MODE_VISIBLE


func current_settlement() -> Settlement:
	return World.settlement(_current_settlement) if _current_settlement != &"" else null


## Разговор всегда поверх всего и всегда на паузе: пропустить реплику, потому
## что в этот момент машину сносило с дюны, — плохой опыт.
func _on_dialogue_requested(dialogue_id: StringName) -> void:
	EventBus.screen_requested.emit(&"dialogue", {"dialogue": String(dialogue_id)})


## Взаимодействие. Из машины — это по-прежнему «въехал в посёлок, открылась
## биржа». Пешком — по тому, к чему подошёл: у двери мастерской открывается
## мастерская, у почты — почта, у своего дома — гараж, у машины — посадка.
##
## Одна клавиша на всё сознательно: список того, что можно сделать, виден в
## подсказке над прицелом, и лишний выбор между «войти» и «поговорить» тут
## ничего не даёт.
func _interact() -> void:
	if on_foot:
		_interact_on_foot()
		return
	var here := current_settlement()
	if here == null:
		EventBus.notify("Здесь не с кем говорить", &"warning")
		return
	EventBus.screen_requested.emit(&"contracts", {"settlement": String(here.id)})


func _interact_on_foot() -> void:
	var target := reachable()
	if target.is_empty():
		EventBus.notify("Здесь не к чему подойти", &"warning")
		return
	match StringName(target["what"]):
		&"vehicle":
			board_vehicle()
		&"door":
			_enter_building(target["door"])
		_:
			EventBus.notify("Ничего не происходит")


## Что сейчас в досягаемости пешего игрока. Возвращает пустой словарь, если
## ничего. Тот же вызов использует подсказка в интерфейсе — чтобы написанное
## в подсказке и сделанное по клавише не разошлись.
func reachable() -> Dictionary:
	if not on_foot or walker == null:
		return {}
	var from := walker.global_position
	if from.distance_to(vehicle.global_position) < _boarding_distance():
		return {"what": &"vehicle", "name": vehicle.config.display_name}
	if places != null:
		var doors := places.doors_near(from, 5.0)
		if not doors.is_empty():
			var best: Dictionary = doors[0]
			for door: Dictionary in doors:
				if (door["world"] as Vector3).distance_to(from) \
					< (best["world"] as Vector3).distance_to(from):
					best = door
			return {"what": &"door", "name": best["name"], "door": best}
	return {}


func _enter_building(door: Dictionary) -> void:
	var settlement_id := StringName(door.get("settlement", ""))
	var kind := StringName(door.get("kind", ""))
	var payload := {"settlement": String(settlement_id)}
	match kind:
		&"guild", &"post":
			EventBus.screen_requested.emit(&"contracts", payload)
		&"workshop", &"market", &"guesthouse":
			EventBus.screen_requested.emit(&"settlement", payload)
		&"majlis":
			EventBus.screen_requested.emit(&"settlement", payload)
		&"mansion":
			if bool(GameState.flag(&"met_valya")):
				EventBus.dialogue_requested.emit(&"valya_first_meeting")
			else:
				EventBus.notify("Дверь закрыта. Хозяин, видимо, в эфире")
		&"home":
			_enter_home(StringName(door.get("home", "")))
		_:
			EventBus.notify(String(door.get("name", "Дверь")))


func _enter_home(home_id: StringName) -> void:
	var home := Homes.get_by_id(home_id)
	if home == null:
		return
	if not home.is_owned():
		if home.is_available() and home.price > 0.0:
			EventBus.notify("%s — продаётся за %s. Спросите в посёлке."
				% [home.name, Settings.format_money(home.price)])
		else:
			EventBus.notify("Дверь заперта. Это не ваш дом")
		return
	EventBus.screen_requested.emit(&"garage", {
		"home": String(home_id),
		"settlement": String(home.settlement),
	})


func _show_loading(text: String) -> void:
	_loading = Control.new()
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color(0.043, 0.039, 0.055)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(background)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(label)
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.name = "Loading"
	layer.add_child(_loading)
	add_child(layer)


func _hide_loading() -> void:
	var layer := get_node_or_null("Loading")
	if layer != null:
		layer.queue_free()
	_loading = null
