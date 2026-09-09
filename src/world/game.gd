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

var _loading: Control
var _poll_timer: float = 0.0
var _current_settlement: StringName = &""
var is_world_ready: bool = false
var _headlights: Array[SpotLight3D] = []
var _headlights_on: bool = false


func _ready() -> void:
	Catalog.ensure_loaded()
	_show_loading("Собираем мир…")
	if World.is_ready and Rng.world_seed == _expected_seed():
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

	camera = VehicleCamera.new()
	camera.name = "Camera"
	camera.base_fov = Settings.fov
	add_child(camera)
	camera.follow(vehicle)

	# Ближнее кольцо строим сразу и синхронно: без земли под колёсами машина
	# успевает улететь в пустоту за те кадры, пока считаются потоки.
	terrain.begin(World.field, vehicle)
	terrain.build_immediate(vehicle.global_position)

	_hide_loading()
	is_world_ready = true
	world_ready.emit()
	EventBus.notify("Добро пожаловать в Хамсин")


func _spawn_vehicle() -> void:
	vehicle = VehicleBody.new()
	vehicle.name = "Vehicle"
	vehicle.config_id = GameState.vehicle_id
	vehicle.player_controlled = true
	vehicle.surface_provider = World.surface_at
	add_child(vehicle)

	var visuals := ChassisBuilder.build(vehicle.config)
	var wheel_nodes: Array[Node3D] = visuals["wheels"]
	for node: Node3D in wheel_nodes:
		vehicle.add_child(node)
	vehicle.attach_visuals(visuals["chassis"], wheel_nodes)
	_headlights = visuals["headlights"]

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

	_poll_timer += delta
	if _poll_timer >= SETTLEMENT_POLL:
		_poll_timer = 0.0
		_check_settlement()
		_auto_headlights()


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


func current_settlement() -> Settlement:
	return World.settlement(_current_settlement) if _current_settlement != &"" else null


func _interact() -> void:
	var here := current_settlement()
	if here == null:
		EventBus.notify("Здесь не с кем говорить", &"warning")
		return
	EventBus.screen_requested.emit(&"contracts", {"settlement": String(here.id)})


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
