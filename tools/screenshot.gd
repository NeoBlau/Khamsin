extends Node
## Снимает мир в PNG. Инструмент разработки: им проверяется, что сцена
## действительно собирается и выглядит как задумано, без запуска игры руками.
##
## Запуск:
##   xvfb-run -a godot --path games/khamsin --rendering-driver vulkan \
##     --resolution 1280x720 res://tools/screenshot.tscn -- \
##     --out /tmp/shot.png --seed 20260907 --hour 8.5 --drive 4
##
## Ключ --cheap (по умолчанию включён) снимает тени, сглаживание и свечение.
## Это только для программного растеризатора в контейнере: на настоящей
## видеокарте всё это стоит копейки и должно быть включено.

var _out: String = "user://shot.png"
var _seed: int = 20260907
var _hour: float = 8.0
var _drive: float = 0.0
var _throttle: float = 0.55
var _steer: float = 0.0
var _camera_mode: int = 0
var _warmup: int = 8
var _cheap: bool = true
var _game: Node3D


func _ready() -> void:
	_out = _argument("--out", _out)
	_seed = int(_argument("--seed", str(_seed)))
	_hour = float(_argument("--hour", str(_hour)))
	_drive = float(_argument("--drive", str(_drive)))
	_throttle = float(_argument("--throttle", str(_throttle)))
	_steer = float(_argument("--steer", "0"))
	_camera_mode = int(_argument("--camera", "0"))
	_warmup = int(_argument("--warmup", str(_warmup)))
	_cheap = _argument("--cheap", "1") == "1"

	# Радиус прорисовки и расстояния переключения LOD на снимках уменьшаются:
	# программный растеризатор считает четыре километра ландшафта минутами.
	Config.chunk_view_radius = int(_argument("--radius", str(Config.chunk_view_radius)))
	var lod_scale := float(_argument("--lod-scale", "1.0"))
	if not is_equal_approx(lod_scale, 1.0):
		var scaled: Array[float] = []
		for distance: float in Config.lod_distances:
			scaled.append(distance * lod_scale)
		Config.lod_distances = scaled
	if _cheap:
		Settings.shadow_quality = 1
		Settings.msaa = 0
		Settings.apply_all()

	var began := Time.get_ticks_msec()
	GameState.new_game(_seed)
	GameState.time_of_day = _hour
	World.build_now(_seed)
	print("мир собран за %d мс" % (Time.get_ticks_msec() - began))
	# Шейдер с ошибкой компиляции не рисуется молча: поверхность просто
	# исчезает, и это очень легко принять за проблему в геометрии.
	for path: String in ["res://shaders/terrain.gdshader", "res://shaders/sky.gdshader"]:
		var shader: Shader = load(path)
		var uniforms := shader.get_shader_uniform_list()
		print("  %s: униформ %d" % [path.get_file(), uniforms.size()])

	began = Time.get_ticks_msec()
	_game = load("res://scenes/game.tscn").instantiate()
	add_child(_game)
	await _game.world_ready
	print("сцена готова за %d мс" % (Time.get_ticks_msec() - began))

	var at := _argument("--at", "")
	if at != "":
		var parts := at.split(",")
		var x := float(parts[0])
		var z := float(parts[1]) if parts.size() > 1 else 0.0
		_game.terrain.build_immediate(Vector3(x, 0.0, z))
		_game.vehicle.global_position = Vector3(x, World.height(x, z) + 1.5, z)
		_game.vehicle.linear_velocity = Vector3.ZERO
		for _i: int in 240:
			await get_tree().physics_frame

	_game.camera.mode = _camera_mode as VehicleCamera.Mode
	if _cheap:
		var env: Environment = _game.sky.environment.environment
		env.glow_enabled = false
		env.fog_aerial_perspective = 0.0
	if _argument("--paint", "0") == "1":
		var terrain_material := (_game.terrain as TerrainManager).material()
		terrain_material.set_shader_parameter("sand_colour", Color(1.0, 0.0, 1.0))
		terrain_material.set_shader_parameter("sand_shadow", Color(0.5, 0.0, 0.5))
		terrain_material.set_shader_parameter("gravel_colour", Color(0.0, 1.0, 0.0))
		terrain_material.set_shader_parameter("rock_colour", Color(0.0, 0.4, 0.0))
		terrain_material.set_shader_parameter("track_colour", Color(0.0, 0.0, 1.0))
		var used := 0
		for child: Node in _game.terrain.get_children():
			var visual: MeshInstance3D = child.get_node_or_null("Surface")
			if visual != null and visual.material_override == terrain_material:
				used += 1
		print("чанков с материалом ландшафта: %d из %d" % [used, _game.terrain.get_child_count()])

	var debug_view := int(_argument("--debug", "0"))
	if debug_view > 0:
		_game.terrain.material().set_shader_parameter("debug_view", debug_view)
	if _argument("--shadows", "1") == "0":
		_game.sky.sun.shadow_enabled = false
	var sun_override := float(_argument("--sun", "0"))
	var ambient_override := float(_argument("--ambient", "-1"))
	if sun_override > 0.0 or ambient_override >= 0.0:
		_game.sky.set_process(false)
		if sun_override > 0.0:
			_game.sky.sun.light_energy = sun_override
		if ambient_override >= 0.0:
			_game.sky.environment.environment.ambient_light_energy = ambient_override

	if _drive > 0.0:
		began = Time.get_ticks_msec()
		_game.vehicle.input.throttle = _throttle
		_game.vehicle.input.steer = _steer
		var steps := int(_drive * float(Engine.physics_ticks_per_second))
		for _i: int in steps:
			await get_tree().physics_frame
		_game.vehicle.input.throttle = 0.0
		_game.vehicle.input.steer = 0.0
		print("проехали %.1f с за %d мс" % [_drive, Time.get_ticks_msec() - began])

	var top := float(_argument("--top", "0"))
	if top > 0.0:
		# Взгляд строго вниз с заданной высоты. Однозначная проверка: в кадре
		# либо земля, либо её нет, и спорить не о чем.
		_game.camera.set_physics_process(false)
		var truck: VehicleBody = _game.vehicle
		var above: Vector3 = truck.global_position + Vector3.UP * top
		_game.camera.global_transform = Transform3D(
			Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), above
		)
		_game.camera.fov = 70.0

	for i: int in _warmup:
		var frame_began := Time.get_ticks_msec()
		await get_tree().process_frame
		print("  кадр %d/%d — %d мс" % [i + 1, _warmup, Time.get_ticks_msec() - frame_began])
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_out)
	if error != OK:
		push_error("Скриншот не сохранён: %d" % error)
	else:
		print("Скриншот: %s (%dx%d)" % [_out, image.get_width(), image.get_height()])
	print("Позиция: %s" % _game.vehicle.global_position)
	print("Скорость: %.1f м/с, передача %d, обороты %.0f"
		% [_game.vehicle.speed, _game.vehicle.drivetrain.gear, _game.vehicle.drivetrain.rpm()])
	print("Грунт: %s" % World.surface_at(_game.vehicle.global_position).display_name)
	print("Погода: %s" % _game.weather.forecast_line())
	var env_now: Environment = _game.sky.environment.environment
	print("Солнце: энергия %.2f, направление %s, цвет %s"
		% [_game.sky.sun.light_energy, -_game.sky.sun.global_transform.basis.z, _game.sky.sun.light_color])
	print("Окружение: ambient %.2f, вклад неба %.2f, экспозиция %.2f, туман %.5f"
		% [env_now.ambient_light_energy, env_now.ambient_light_sky_contribution,
		env_now.tonemap_exposure, env_now.fog_density])
	var streamer: TerrainManager = _game.terrain
	var here: Vector2i = streamer.world_to_chunk(_game.vehicle.global_position)
	for coordinate: Vector2i in [here, here + Vector2i(1, 0), here + Vector2i(0, 1)]:
		var chunk: TerrainChunk = streamer.get_node_or_null(
			"Chunk_%d_%d" % [coordinate.x, coordinate.y]
		)
		if chunk == null:
			print("  чанк %s: НЕТ" % coordinate)
			continue
		var visual: MeshInstance3D = chunk.get_node_or_null("Surface")
		var mesh: Mesh = visual.mesh if visual != null else null
		print("  чанк %s: lod %d, коллизия %s, меш %s, поверхностей %d, AABB %s, материал %s, виден %s"
			% [coordinate, chunk.lod, chunk.has_collision, mesh != null,
			mesh.get_surface_count() if mesh != null else -1,
			visual.get_aabb() if visual != null else "-",
			visual.material_override != null if visual != null else false,
			visual.visible if visual != null else false])
	print("Чанков: %d загружено, %d в очереди"
		% [_game.terrain.loaded_chunk_count(), _game.terrain.pending_count()])
	get_tree().quit()


func _argument(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return fallback
