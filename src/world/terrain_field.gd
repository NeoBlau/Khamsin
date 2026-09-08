class_name TerrainField
extends RefCounted
## Аналитический рельеф: высота и покрытие как чистые функции от координат.
##
## Ключевое свойство — никакого состояния и никаких узлов. Одну и ту же функцию
## зовут генератор меша в рабочем потоке, генератор коллизии, построитель
## маршрутов и запрос «что под колесом». Поэтому картинка, коллизия и грунт
## заведомо описывают одну и ту же землю: расхождению просто неоткуда взяться.
##
## Дюны собраны не из симметричного синуса, а из асимметричного профиля:
## длинный пологий наветренный склон и короткий крутой подветренный. Это и есть
## разница между «холмики» и «пустыня»: вверх заезжаешь, вниз падаешь.

var world_seed: int = 0

var macro_amplitude: float = 120.0
var dune_amplitude: float = 32.0
var dune_wavelength: float = 380.0
var dune_windward_fraction: float = 0.72
var wind_direction: Vector2 = Vector2(0.81, 0.58)
var world_extent: float = 10000.0

## Маршруты, которые выравнивают под собой землю. Может быть null — тогда
## рельеф чистый, без накатанных колей.
var routes: RouteNetwork = null
## Поселения: id → {position: Vector2, radius: float, height: float}.
var settlements: Array[Dictionary] = []

var _macro: FastNoiseLite
var _ridge: FastNoiseLite
var _detail: FastNoiseLite
var _warp: FastNoiseLite
var _field_mask: FastNoiseLite
var _surface_noise: FastNoiseLite


func _init(seed_value: int = 0) -> void:
	setup(seed_value)


func setup(seed_value: int) -> void:
	world_seed = seed_value

	_macro = _make_noise(seed_value + 11, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 5200.0, 5, 0.48)
	_ridge = _make_noise(seed_value + 23, FastNoiseLite.TYPE_SIMPLEX, 1.0 / 1900.0, 4, 0.5)
	_detail = _make_noise(seed_value + 37, FastNoiseLite.TYPE_SIMPLEX, 1.0 / 34.0, 3, 0.45)
	# Искажение фазы дюн обязано быть очень плавным. Его градиент складывается
	# с базовой частотой гряд, и мелкий шум здесь локально удваивает крутизну
	# подветренного склона — песок таких стенок не держит.
	_warp = _make_noise(seed_value + 53, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 3200.0, 2, 0.5)
	_field_mask = _make_noise(seed_value + 71, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 3400.0, 3, 0.5)
	_surface_noise = _make_noise(seed_value + 97, FastNoiseLite.TYPE_SIMPLEX, 1.0 / 260.0, 2, 0.5)


static func _make_noise(
	seed_value: int, type: FastNoiseLite.NoiseType, frequency: float, octaves: int, gain: float
) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = type
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain
	return noise


## Переносит настройки из Config. Отдельным вызовом, потому что в рабочем
## потоке к автолоаду обращаться нельзя.
func apply_config() -> void:
	macro_amplitude = Config.macro_amplitude
	dune_amplitude = Config.dune_amplitude
	dune_wavelength = Config.dune_wavelength
	dune_windward_fraction = Config.dune_windward_fraction
	wind_direction = Vector2(cos(Config.dune_wind_angle), sin(Config.dune_wind_angle))
	world_extent = Config.world_extent


# --- Высота ----------------------------------------------------------------

## Рельеф без дорог и посёлков. По нему прокладываются маршруты — иначе дорога
## выравнивала бы землю, по которой её же и прокладывают.
func base_height(x: float, z: float) -> float:
	var macro := _macro.get_noise_2d(x, z) * macro_amplitude
	# Гряды: модуль шума даёт складки с острыми гребнями, как выветренные
	# скальные выходы между песчаными полями.
	var ridge := (0.5 - absf(_ridge.get_noise_2d(x, z))) * 2.0 * 18.0
	var dunes := dune_height(x, z)
	var detail := _detail.get_noise_2d(x, z) * 1.1
	return macro + ridge + dunes + detail + _border_rise(x, z)


## Итоговая высота: базовый рельеф, выровненный дорогами и площадками посёлков.
func height(x: float, z: float) -> float:
	var h := base_height(x, z)
	# Порядок важен: сначала дорога подстраивается под рельеф, потом площадка
	# посёлка накрывает всё внутри своего радиуса. Наоборот — и дорога, входя в
	# посёлок, продавливала бы в нём канаву.
	if routes != null:
		h = routes.flatten(x, z, h)
	h = _apply_settlements(x, z, h)
	return h


func height_at(point: Vector3) -> float:
	return height(point.x, point.z)


## Сила и высота дюнного поля в точке. Вынесено отдельно: тем же числом
## определяется, где песок рыхлый, а где под ним твёрдое дно.
func dune_mask(x: float, z: float) -> float:
	return clampf(smoothstep(-0.12, 0.42, _field_mask.get_noise_2d(x, z)), 0.0, 1.0)


## Вклад одних только дюн, метры. Публичный, потому что по нему решается и
## рыхлость песка, и вид с карты, и на нём удобно проверять форму профиля.
func dune_height(x: float, z: float) -> float:
	var mask := dune_mask(x, z)
	if mask <= 0.001:
		return 0.0
	var along := (x * wind_direction.x + z * wind_direction.y) / dune_wavelength
	# Искажение фазы: без него дюны идут идеально параллельными полосами и
	# читаются как обои, а не как эрг.
	along += _warp.get_noise_2d(x, z) * 0.7
	var primary := _dune_profile(fposmod(along, 1.0))

	# Вторая система под другим углом и вдвое короче — она ломает регулярность
	# и делает межгрядовые коридоры непохожими друг на друга.
	var cross_dir := Vector2(-wind_direction.y, wind_direction.x).rotated(0.55)
	var across := (x * cross_dir.x + z * cross_dir.y) / (dune_wavelength * 0.44)
	across += _warp.get_noise_2d(z * 0.7, x * 0.7) * 0.6
	var secondary := _dune_profile(fposmod(across, 1.0))

	return (primary * 0.82 + secondary * 0.18) * dune_amplitude * mask


## Профиль дюны: пологий подъём против ветра и обрыв за гребнем.
func _dune_profile(t: float) -> float:
	var w := clampf(dune_windward_fraction, 0.05, 0.95)
	if t < w:
		var u := t / w
		return u * u * (3.0 - 2.0 * u)
	var u := (t - w) / (1.0 - w)
	return 1.0 - u * u * (3.0 - 2.0 * u)


## Край карты: земля уходит вверх непроходимой грядой. Честнее невидимой стены
## и не требует объяснений — дальше просто не заехать.
func _border_rise(x: float, z: float) -> float:
	var reach := maxf(absf(x), absf(z))
	var start := world_extent - 900.0
	if reach <= start:
		return 0.0
	var t := clampf((reach - start) / 900.0, 0.0, 1.0)
	return t * t * 260.0


func _apply_settlements(x: float, z: float, h: float) -> float:
	for entry: Dictionary in settlements:
		var position: Vector2 = entry["position"]
		var radius: float = entry["radius"]
		var distance := Vector2(x, z).distance_to(position)
		if distance > radius:
			continue
		# Плоская площадка в центре и мягкий скат к естественному рельефу.
		var blend := smoothstep(radius * 0.45, radius, distance)
		h = lerpf(float(entry["height"]), h, blend)
	return h


## Нормаль по конечным разностям. Шаг берётся от размера ячейки: на дальних
## LOD мелкие складки в нормаль попадать не должны, иначе дюны рябят.
func normal(x: float, z: float, step: float = 1.5) -> Vector3:
	var left := height(x - step, z)
	var right := height(x + step, z)
	var back := height(x, z - step)
	var front := height(x, z + step)
	return Vector3(left - right, 2.0 * step, back - front).normalized()


## Уклон в точке, 0 — плоскость, 1 — сорок пять градусов.
func slope(x: float, z: float, step: float = 3.0) -> float:
	var n := normal(x, z, step)
	return clampf(tan(acos(clampf(n.y, 0.0, 1.0))), 0.0, 4.0)


# --- Покрытие --------------------------------------------------------------

## Что под колесом. Тот же расчёт идёт в цвет вершин, поэтому игрок видит
## границу песка и хамады ровно там, где она есть в физике.
func surface_at(x: float, z: float) -> Surface:
	return Surface.get_by_id(surface_id_at(x, z))


func surface_id_at(x: float, z: float) -> StringName:
	if routes != null and routes.on_track(x, z):
		return &"track"

	var steepness := slope(x, z, 4.0)
	var mask := dune_mask(x, z)
	var grain := _surface_noise.get_noise_2d(x, z)

	# Крутой склон без песка — это выветренная скала.
	if steepness > 0.7 and mask < 0.35:
		return &"rock"
	if mask > 0.55:
		# Внутри дюнного поля рыхло у гребней и на подветренных склонах,
		# плотнее в межгрядовых коридорах, где песок сдут.
		var crest := dune_height(x, z) / maxf(dune_amplitude, 1.0)
		if crest > 0.45 or steepness > 0.35:
			return &"sand_soft"
		return &"sand_firm"
	if mask > 0.22:
		return &"sand_firm" if grain > 0.05 else &"gravel"
	# Солончак: очень ровно и низко.
	if steepness < 0.05 and grain < -0.35:
		return &"sabkha"
	return &"gravel"


## Веса покрытий для шейдера: песок, гравий/камень, накатка. Сумма равна
## единице, поэтому их можно класть прямо в цвет вершины.
func surface_weights(x: float, z: float) -> Color:
	var id := surface_id_at(x, z)
	match id:
		&"sand_soft":
			return Color(1.0, 0.0, 0.0)
		&"sand_firm":
			return Color(0.75, 0.25, 0.0)
		&"sabkha":
			return Color(0.35, 0.65, 0.0)
		&"track":
			return Color(0.15, 0.15, 0.7)
		&"rock":
			return Color(0.0, 1.0, 0.0)
		_:
			return Color(0.25, 0.75, 0.0)


## Точка внутри карты, а не в пограничной гряде.
func is_inside(x: float, z: float) -> bool:
	return maxf(absf(x), absf(z)) < world_extent - 950.0
