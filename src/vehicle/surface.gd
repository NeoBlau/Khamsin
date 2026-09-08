class_name Surface
extends RefCounted
## Свойства покрытия под колесом.
##
## Числа взяты по порядку величины из внедорожной механики (Bekker, Wong
## «Theory of Ground Vehicles»), а не выведены строго. Цель — чтобы рыхлый
## песок ощущался рыхлым песком, а не чтобы сойтись с полигонными замерами.

var id: StringName = &"gravel"
var display_name: String = ""
## Множитель к пиковому сцеплению шины.
var grip: float = 1.0
## Потери на гистерезис в самой резине. Потери в грунте сюда не входят: за них
## отвечает `bulldoze`, иначе одно и то же считалось бы дважды. Поэтому разброс
## между покрытиями небольшой — деформация шины мало зависит от того, по чему
## она катится, а вот по чему она катится, решает всё остальное.
var rolling_resistance: float = 0.03
## Просадка колеса в метрах при давлении в пятне 100 кПа.
var sink_coefficient: float = 0.0
## Показатель степени в законе «давление — просадка».
var sink_exponent: float = 1.0
## Сопротивление сгребанию и уплотнению грунта, Н на ньютон нагрузки на метр
## просадки. На песке это основная потеря — и именно она падает почти вдвое,
## когда колёса спускают.
var bulldoze: float = 0.0
## Сколько пыли поднимает колесо, 0..1.
var dust: float = 0.0
## Амплитуда микронеровностей, метры. Идёт в тряску подвески и в звук.
var roughness: float = 0.01
## Пробуксовка на этом покрытии выкапывает яму и делает его хуже.
var diggable: bool = false

static var _library: Dictionary[StringName, Surface] = {}


static func _make(
	id: StringName,
	display_name: String,
	grip: float,
	rolling: float,
	sink_c: float,
	sink_e: float,
	bulldoze: float,
	dust: float,
	roughness: float,
	diggable: bool
) -> Surface:
	var s := Surface.new()
	s.id = id
	s.display_name = display_name
	s.grip = grip
	s.rolling_resistance = rolling
	s.sink_coefficient = sink_c
	s.sink_exponent = sink_e
	s.bulldoze = bulldoze
	s.dust = dust
	s.roughness = roughness
	s.diggable = diggable
	return s


static func library() -> Dictionary[StringName, Surface]:
	if not _library.is_empty():
		return _library
	#                            id           название          grip   Crr   sink  exp  bull  dust  rough  dig
	_library[&"asphalt"] = _make(&"asphalt", "асфальт", 1.00, 0.012, 0.000, 1.0, 0.00, 0.02, 0.004, false)
	_library[&"track"] = _make(&"track", "накатка", 0.86, 0.016, 0.010, 0.9, 0.20, 0.35, 0.020, false)
	_library[&"gravel"] = _make(&"gravel", "хамада", 0.74, 0.020, 0.018, 0.9, 0.35, 0.45, 0.045, false)
	_library[&"rock"] = _make(&"rock", "камень", 0.92, 0.022, 0.000, 1.0, 0.00, 0.10, 0.090, false)
	_library[&"sabkha"] = _make(&"sabkha", "себха", 0.80, 0.014, 0.006, 1.2, 0.15, 0.15, 0.012, false)
	_library[&"sand_firm"] = _make(&"sand_firm", "плотный песок", 0.64, 0.018, 0.050, 1.0, 0.45, 0.75, 0.025, true)
	_library[&"sand_soft"] = _make(&"sand_soft", "рыхлый песок", 0.52, 0.020, 0.110, 1.25, 0.61, 1.00, 0.030, true)
	return _library


static func get_by_id(id: StringName) -> Surface:
	var lib := library()
	var found: Surface = lib.get(id)
	return found if found != null else lib[&"gravel"]


static func default_surface() -> Surface:
	return get_by_id(&"gravel")
