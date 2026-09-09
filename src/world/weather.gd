class_name Weather
extends Node
## Погода и ветер.
##
## Не декорация: ветер — это сила на кузов, пыль — это дальность видимости, а
## буря — это причина не выезжать. Состояние выводится из игрового времени и
## сида, поэтому прогноз в кабине не врёт и после перезагрузки сохранения буря
## начинается в тот же час.

signal changed(kind: StringName, intensity: float)

enum Kind { CLEAR, HAZE, WIND, SANDSTORM }

const KIND_NAMES: Dictionary[Kind, String] = {
	Kind.CLEAR: "ясно",
	Kind.HAZE: "дымка",
	Kind.WIND: "ветер",
	Kind.SANDSTORM: "песчаная буря",
}

var kind: Kind = Kind.CLEAR
## 0..1 — насколько сильно выражено текущее состояние.
var intensity: float = 0.0
## Скорость ветра у земли, м/с.
var wind_speed: float = 2.0
var wind_direction: Vector2 = Vector2(0.81, 0.58)
## Взвесь в воздухе, 0..1. Идёт и в небо, и в туман, и в дальность прорисовки.
var dust: float = 0.1
## Температура воздуха, °C. Влияет на груз и на охлаждение двигателя.
var temperature: float = 32.0

var _target_intensity: float = 0.0
var _target_kind: Kind = Kind.CLEAR
var _next_change_hour: float = 0.0


func _ready() -> void:
	_roll(GameState.total_hours())
	intensity = _target_intensity
	kind = _target_kind
	_apply()


func _process(delta: float) -> void:
	var now := GameState.total_hours()
	if now >= _next_change_hour:
		_roll(now)
	# Погода меняется плавно: стена песка, включающаяся за кадр, читается как
	# баг, даже когда она задумана.
	intensity = move_toward(intensity, _target_intensity, delta * 0.06)
	if kind != _target_kind and intensity < 0.05:
		kind = _target_kind
		changed.emit(kind, intensity)
		EventBus.weather_changed.emit(kind_id(), intensity)
	_apply()


## Бросок погоды на ближайшие часы. Детерминирован: сид плюс номер интервала.
func _roll(now: float) -> void:
	var slot := floori(now / 5.0)
	var rng := Rng.local(slot, 0x57EA)
	var roll := rng.randf()
	if roll < 0.52:
		_target_kind = Kind.CLEAR
		_target_intensity = rng.randf_range(0.05, 0.25)
	elif roll < 0.78:
		_target_kind = Kind.HAZE
		_target_intensity = rng.randf_range(0.25, 0.5)
	elif roll < 0.93:
		_target_kind = Kind.WIND
		_target_intensity = rng.randf_range(0.4, 0.7)
	else:
		_target_kind = Kind.SANDSTORM
		_target_intensity = rng.randf_range(0.65, 1.0)
	# Направление ветра гуляет вокруг господствующего, но не разворачивается
	# на сто восемьдесят градусов: дюны сложены им же за тысячи лет.
	var base := Config.dune_wind_angle
	var angle := base + rng.randf_range(-0.7, 0.7)
	wind_direction = Vector2(cos(angle), sin(angle))
	_next_change_hour = float(slot + 1) * 5.0


func _apply() -> void:
	match kind:
		Kind.CLEAR:
			wind_speed = lerpf(1.0, 5.0, intensity)
			dust = lerpf(0.04, 0.12, intensity)
		Kind.HAZE:
			wind_speed = lerpf(3.0, 8.0, intensity)
			dust = lerpf(0.18, 0.38, intensity)
		Kind.WIND:
			wind_speed = lerpf(8.0, 17.0, intensity)
			dust = lerpf(0.3, 0.55, intensity)
		Kind.SANDSTORM:
			wind_speed = lerpf(16.0, 30.0, intensity)
			dust = lerpf(0.6, 1.0, intensity)

	# Суточный ход температуры: днём под пятьдесят, ночью ближе к десяти.
	var hour := GameState.time_of_day
	var solar := cos((hour - 15.0) / 24.0 * TAU)
	temperature = 27.0 + solar * 17.0 - dust * 6.0


func kind_id() -> StringName:
	match kind:
		Kind.HAZE: return &"haze"
		Kind.WIND: return &"wind"
		Kind.SANDSTORM: return &"sandstorm"
		_: return &"clear"


func kind_name() -> String:
	return KIND_NAMES.get(kind, "ясно")


## Вектор скорости воздуха для аэродинамики машины.
func wind_vector() -> Vector3:
	return Vector3(wind_direction.x, 0.0, wind_direction.y) * wind_speed


## Дальность, на которой уже ничего не разобрать, метры.
func visibility() -> float:
	return lerpf(6000.0, 90.0, pow(clampf(dust, 0.0, 1.0), 0.7))


func is_dangerous() -> bool:
	return kind == Kind.SANDSTORM and intensity > 0.5


## Короткая сводка для приборной панели и для диспетчера в диалогах.
func forecast_line() -> String:
	return "%s, ветер %.0f м/с, видимость %s" % [
		kind_name(), wind_speed, Settings.format_distance(visibility())
	]
