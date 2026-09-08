class_name TireModel
extends RefCounted
## Шина: сцепление при комбинированном скольжении и поведение в мягком грунте.
##
## Формула Пацейки в нормированном виде — проскальзывание делится на своё
## пиковое значение, поэтому одна и та же тройка (B, C, E) описывает и
## продольный, и боковой канал, а настраиваются только точки пика в конфиге.
## При B = 2.0, C = 1.6, E = 0.6 максимум приходится ровно на s = 1, а на
## s = 6.7 (полная блокировка) остаётся 0.79 от пика — это близко к тому, что
## меряют на реальной грунтовой резине.

const B := 2.0
const C := 1.6
const E := 0.6

## Ниже этой скорости комбинированное скольжение считать бессмысленно —
## работает только релаксация каркаса.
const CREEP_SPEED := 0.35


## Безразмерная кривая сцепления. На входе — модуль нормированного скольжения,
## на выходе — доля от максимума, 0..1.
static func curve(s: float) -> float:
	var bs := B * s
	var x := bs - E * (bs - atan(bs))
	return sin(C * atan(x))


## Продольная и боковая силы для одного колеса.
##
## kappa   — проскальзывание (w*r - v_x) / |v_x|, уже отфильтрованное релаксацией
## alpha   — угол увода, радианы, знак совпадает со знаком боковой скорости
## load    — нормальная нагрузка, Н
## mu      — пиковый коэффициент сцепления с учётом покрытия и износа
## Возвращает Vector2(Fx, Fy) в системе пятна контакта: X вперёд, Y вправо.
static func forces(
	kappa: float,
	alpha: float,
	load: float,
	mu: float,
	kappa_peak: float,
	alpha_peak: float
) -> Vector2:
	if load <= 0.0:
		return Vector2.ZERO
	var sx := kappa / maxf(kappa_peak, 0.001)
	var sy := tan(clampf(alpha, -1.4, 1.4)) / maxf(tan(alpha_peak), 0.001)
	var s := sqrt(sx * sx + sy * sy)
	if s < 1e-5:
		return Vector2.ZERO
	var total := mu * load * curve(s)
	# Эллипс трения: суммарная сила делится между каналами по направлению
	# скольжения. Именно отсюда берётся «газ в повороте съедает поворот».
	return Vector2(total * sx / s, -total * sy / s)


## Сцепление с поправкой на нагрузку и износ протектора.
##
## Шина под большей нагрузкой цепляется хуже в пересчёте на ньютон — из-за
## этого гружёная машина тормозит длиннее, чем «во столько же раз тяжелее».
static func effective_mu(
	base_mu: float,
	surface_grip: float,
	load: float,
	nominal_load: float,
	load_sensitivity: float,
	wear: float
) -> float:
	var load_ratio := load / maxf(nominal_load, 1.0)
	var load_factor := 1.0 - load_sensitivity * (load_ratio - 1.0)
	load_factor = clampf(load_factor, 0.45, 1.35)
	# Лысая резина на песке теряет меньше, чем на асфальте: там работает не
	# протектор, а форма пятна. Поэтому износ взвешен сцеплением покрытия.
	var wear_factor := 1.0 - clampf(wear, 0.0, 1.0) * 0.35 * clampf(surface_grip, 0.0, 1.0)
	return maxf(base_mu * surface_grip * load_factor * wear_factor, 0.05)


## Площадь пятна контакта, м². Первое приближение честное и очень простое:
## воздух в шине держит нагрузку, поэтому площадь равна нагрузке, делённой на
## давление. Каркас берёт на себя часть нагрузки — это CARCASS_PRESSURE, без
## неё пустая шина давала бы бесконечное пятно.
##
## Отсюда же берётся весь смысл спускать колёса в дюнах: с 2.4 до 1.0 бар
## пятно вырастает примерно вдвое, а давление на песок во столько же падает.
const CARCASS_PRESSURE := 45000.0
## Пятно уже шины: плечи протектора в контакт не входят.
const PATCH_WIDTH_RATIO := 0.85


static func patch_area(load: float, pressure_bar: float, width: float, radius: float) -> float:
	if load <= 0.0:
		return 0.0
	var effective_pressure := maxf(pressure_bar, 0.15) * 100000.0 + CARCASS_PRESSURE
	var area := load / effective_pressure
	var patch_width := width * PATCH_WIDTH_RATIO
	# Пятно не может быть длиннее полутора радиусов — дальше шина просто
	# складывается, и модель перестаёт что-либо описывать.
	var length := clampf(area / maxf(patch_width, 0.02), radius * 0.1, radius * 1.5)
	return length * patch_width


static func patch_length(load: float, pressure_bar: float, width: float, radius: float) -> float:
	return patch_area(load, pressure_bar, width, radius) / maxf(width * PATCH_WIDTH_RATIO, 0.02)


## Прогиб шины под нагрузкой, метры. Вертикальная жёсткость растёт с давлением
## почти линейно — на этом же держится ощущение «спущенная шина мягче».
static func deflection(load: float, pressure_bar: float, nominal_pressure: float, radius: float) -> float:
	var stiffness := 350000.0 * (0.25 + 0.75 * maxf(pressure_bar, 0.15) / maxf(nominal_pressure, 0.5))
	return clampf(load / maxf(stiffness, 1000.0), 0.0, radius * 0.35)


## Просадка колеса в грунт, метры. Больше пятно — меньше давление на песок —
## меньше закапывается. Та же обратная связь, что и в реальной пустыне.
static func sinkage(surface: Surface, load: float, patch_area_m2: float) -> float:
	if surface.sink_coefficient <= 0.0 or patch_area_m2 <= 0.0:
		return 0.0
	var pressure_kpa := load / patch_area_m2 / 1000.0
	return surface.sink_coefficient * pow(maxf(pressure_kpa, 0.0) / 100.0, surface.sink_exponent)


## Насколько грунт твёрдый, 0..1. Нужен, чтобы штраф за спущенное колесо
## работал на асфальте и не работал на песке — там всё ровно наоборот.
static func surface_hardness(surface: Surface) -> float:
	return 1.0 / (1.0 + surface.sink_coefficient * 20.0)


## Сопротивление движению: качение по твёрдому плюс сгребание грунта. Всегда
## направлено против качения, поэтому возвращается модулем.
static func motion_resistance(surface: Surface, load: float, sink: float, pressure_bar: float) -> float:
	# Спущенное колесо жуёт само себя на твёрдом покрытии, но на песке эта
	# добавка почти исчезает: там потери не в резине, а в грунте.
	var raw_penalty := clampf(2.4 / maxf(pressure_bar, 0.2), 0.7, 2.4)
	var hardness := surface_hardness(surface)
	var pressure_penalty := lerpf(1.0, raw_penalty, hardness)
	var rolling := surface.rolling_resistance * pressure_penalty * load
	var bulldozing := surface.bulldoze * sink * load
	return maxf(rolling + bulldozing, 0.0)


## Фильтр релаксации каркаса. Шина набирает силу не мгновенно: пока пятно не
## прокатилось на длину релаксации, скольжение «догоняет» истинное. Побочный и
## самый полезный эффект — на нулевой скорости нет деления на ноль.
static func relax(current: float, target: float, speed: float, relaxation_length: float, dt: float) -> float:
	var rate := absf(speed) / maxf(relaxation_length, 0.05)
	# Минимальная скорость сходимости, иначе стоящая машина навсегда запоминает
	# последнее скольжение и уезжает сама.
	rate = maxf(rate, 1.5)
	var alpha := 1.0 - exp(-rate * dt)
	return current + (target - current) * alpha
