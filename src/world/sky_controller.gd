class_name SkyController
extends Node3D
## Небо, солнце и туман.
##
## Всё строится кодом: сцена мира не должна распадаться от того, что кто-то
## случайно подвинул источник света в редакторе. Единственные входы — время
## суток из GameState и состояние погоды.

const SUNRISE := 5.4
const SUNSET := 18.9
## Максимальная высота солнца над горизонтом в полдень, радианы. Пустыня лежит
## в низких широтах, поэтому солнце заходит почти в зенит.
const MAX_ELEVATION := 1.42

var weather: Weather

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var environment: WorldEnvironment

var _sky_material: ShaderMaterial


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 420.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.17
	sun.directional_shadow_split_3 = 0.42
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.4
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.62, 0.70, 0.92)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	add_child(moon)

	environment = WorldEnvironment.new()
	environment.environment = _make_environment()
	add_child(environment)


func _make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	# Карта отражений досчитывается по кусочку за кадр. Небо здесь меняется за
	# минуты, а не за миллисекунды, поэтому полный пересчёт каждый кадр — это
	# отданные впустую проценты кадрового времени.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Не единица: небо в пустыне такое яркое, что при полном вкладе рассеянного
	# света склоны дюн перестают отличаться друг от друга.
	env.ambient_light_sky_contribution = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	# Пустыня очень яркая: без экспозиции ниже единицы песок выгорает в белое.
	env.tonemap_exposure = 0.85

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.6
	# Высотный туман в Godot сгущается НИЖЕ `fog_height`, а не выше. Пустыня
	# лежит около нуля, поэтому большая высота и заметная плотность здесь
	# означают не «дымку у горизонта», а глухую стену в тридцати метрах.
	env.fog_height = 90.0
	env.fog_height_density = 0.0016

	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.4

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.04
	return env


func _process(_delta: float) -> void:
	var hour := GameState.time_of_day
	var day := day_factor(hour)
	_place_sun(hour)
	_tint(day)
	_apply_weather(day)


## 0 — ночь, 1 — день. Плавный переход занимает примерно час до восхода и после
## заката: сумерки в пустыне короткие, но не мгновенные.
static func day_factor(hour: float) -> float:
	if hour <= SUNRISE - 1.0 or hour >= SUNSET + 1.0:
		return 0.0
	if hour < SUNRISE + 0.6:
		return smoothstep(SUNRISE - 1.0, SUNRISE + 0.6, hour)
	if hour > SUNSET - 0.6:
		return 1.0 - smoothstep(SUNSET - 0.6, SUNSET + 1.0, hour)
	return 1.0


func _place_sun(hour: float) -> void:
	var span := SUNSET - SUNRISE
	var t := (hour - SUNRISE) / span
	var elevation := sin(clampf(t, 0.0, 1.0) * PI) * MAX_ELEVATION
	# Азимут ведём с востока на запад с небольшим южным наклоном — тени за день
	# успевают обойти машину, а не просто удлиниться.
	var azimuth := lerpf(-PI * 0.55, PI * 0.55, clampf(t, 0.0, 1.0))
	var direction := Vector3(
		cos(elevation) * sin(azimuth), -sin(elevation), -cos(elevation) * cos(azimuth)
	)
	if hour < SUNRISE or hour > SUNSET:
		# Ночью «солнцем» работает луна: тот же расчёт со сдвигом на полсуток.
		direction = -direction
	sun.look_at_from_position(Vector3.ZERO, direction, Vector3.UP)
	moon.look_at_from_position(Vector3.ZERO, -direction, Vector3.UP)


func _tint(day: float) -> void:
	# У горизонта свет краснеет: путь через атмосферу длиннее, синее рассеяно.
	var low := clampf(1.0 - day, 0.0, 1.0)
	sun.light_color = Color(1.0, 0.93, 0.82).lerp(Color(1.0, 0.55, 0.30), low * 0.9)
	sun.light_energy = lerpf(0.0, 1.5, day)
	moon.light_energy = lerpf(0.09, 0.0, day)
	if environment.environment != null:
		environment.environment.ambient_light_energy = lerpf(0.35, 1.0, day)


func _apply_weather(day: float) -> void:
	var dust := weather.dust if weather != null else 0.12
	var visibility := weather.visibility() if weather != null else 5000.0

	_sky_material.set_shader_parameter("day_factor", day)
	_sky_material.set_shader_parameter("dust", dust)

	var env := environment.environment
	if env == null:
		return
	# Плотность подбирается так, чтобы на заявленной дальности видимости от
	# объекта оставалось около двух процентов — это и есть «уже не разобрать».
	env.fog_density = 4.0 / maxf(visibility, 40.0)
	var fog_colour := Color(0.72, 0.60, 0.42).lerp(Color(0.10, 0.11, 0.16), 1.0 - day)
	env.fog_light_color = fog_colour
	env.fog_light_energy = lerpf(0.12, 0.6, day)
	env.fog_sky_affect = lerpf(0.25, 0.9, dust)
	if weather != null:
		_sky_material.set_shader_parameter("dust_colour", Color(0.68, 0.55, 0.36))


## Дальность прорисовки под текущую погоду. В бурю нет смысла держать в кадре
## четыре километра ландшафта, которого не видно.
func draw_distance() -> float:
	var visibility := weather.visibility() if weather != null else 5000.0
	return clampf(visibility * 1.3, 300.0, 6000.0)
