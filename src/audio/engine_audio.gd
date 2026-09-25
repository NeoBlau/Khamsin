class_name EngineAudio
extends Node3D
## Звук машины: двигатель, качение, ветер, удары подвески.
##
## Двигатель сделан от частоты вспышек, а не от записи. Шестицилиндровый
## четырёхтактник даёт три вспышки на оборот коленвала, то есть rpm/60*3 герц —
## именно эта частота и слышна как «голос» мотора. Петли синтезируются один
## раз на опорной частоте, а дальше тянутся pitch_scale: так звук идёт
## непрерывно от холостых до отсечки, без слышимых ступенек между семплами.
##
## Громкости разведены по смыслу: низ всегда, рык растёт с нагрузкой, впуск
## свистит на высоких оборотах. Отпустил газ — рык уходит, остаётся низ и
## лёгкое потрескивание на сбросе.

## Опорная частота вспышек, на которой синтезированы петли.
const REFERENCE_HZ := 60.0
const CYLINDERS := 6
const STROKE_FACTOR := 0.5  ## четырёхтактник: половина цилиндров за оборот

var vehicle: VehicleBody

var _rumble: AudioStreamPlayer3D
var _growl: AudioStreamPlayer3D
var _intake: AudioStreamPlayer3D
var _roll: AudioStreamPlayer3D
var _wind: AudioStreamPlayer3D
var _thump: AudioStreamPlayer3D
var _last_suspension: float = 0.0
var _smoothed_rpm: float = 700.0
var _smoothed_load: float = 0.0


func _ready() -> void:
	name = "EngineAudio"
	_rumble = _make_player(_build_rumble(), 0.0, 44.0)
	_growl = _make_player(_build_growl(), -60.0, 52.0)
	_intake = _make_player(_build_intake(), -60.0, 30.0)
	_roll = _make_player(_build_roll(), -60.0, 26.0)
	_wind = _make_player(_build_wind(), -60.0, 22.0)
	_thump = _make_player(null, -6.0, 40.0)
	set_physics_process(true)


func _make_player(stream: AudioStream, volume_db: float, max_distance: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = &"Engine"
	player.volume_db = volume_db
	player.max_distance = max_distance
	player.unit_size = 6.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(player)
	if stream != null:
		player.play()
	return player


func _physics_process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	global_position = vehicle.global_position

	var drivetrain := vehicle.drivetrain
	var rpm := drivetrain.rpm() if drivetrain != null else 700.0
	# Сглаживание: обороты в модели дёргаются на каждом такте физики, а ухо
	# слышит эти рывки как дребезг, которого в реальном моторе нет.
	_smoothed_rpm = lerpf(_smoothed_rpm, rpm, clampf(delta * 14.0, 0.0, 1.0))
	var throttle := vehicle.input.throttle if vehicle.input != null else 0.0
	_smoothed_load = lerpf(_smoothed_load, throttle, clampf(delta * 8.0, 0.0, 1.0))

	var firing := _smoothed_rpm / 60.0 * float(CYLINDERS) * STROKE_FACTOR
	var pitch := clampf(firing / REFERENCE_HZ, 0.25, 4.0)
	_rumble.pitch_scale = pitch
	_growl.pitch_scale = pitch
	_intake.pitch_scale = clampf(pitch * 1.02, 0.25, 4.0)

	var revs := clampf((_smoothed_rpm - 600.0) / 2400.0, 0.0, 1.0)
	_rumble.volume_db = linear_to_db(clampf(0.34 + revs * 0.34, 0.001, 1.0))
	_growl.volume_db = linear_to_db(clampf(0.06 + _smoothed_load * (0.30 + revs * 0.42), 0.001, 1.0))
	_intake.volume_db = linear_to_db(clampf(revs * revs * _smoothed_load * 0.5, 0.001, 1.0))

	var speed := absf(vehicle.speed)
	# Качение: громкость от скорости, высота — тоже, но заметно слабее.
	var rolling := clampf(speed / 26.0, 0.0, 1.0)
	_roll.volume_db = linear_to_db(clampf(rolling * 0.42 * _surface_loudness(), 0.001, 1.0))
	_roll.pitch_scale = clampf(0.7 + rolling * 0.75, 0.25, 3.0)
	# Ветер растёт быстрее скорости: аэродинамический шум идёт по кубу.
	var wind := clampf(pow(speed / 30.0, 1.6), 0.0, 1.2)
	_wind.volume_db = linear_to_db(clampf(wind * 0.4, 0.001, 1.0))
	_wind.pitch_scale = clampf(0.8 + wind * 0.5, 0.25, 3.0)

	_check_suspension()


## Насколько шумит грунт под колёсами. Гравий и накатка гремят, песок глушит.
func _surface_loudness() -> float:
	var surface := World.surface_at(vehicle.global_position)
	if surface == null:
		return 1.0
	match surface.id:
		&"rock":
			return 1.0
		&"gravel":
			return 0.9
		&"track", &"asphalt":
			return 0.72
		&"sand_soft":
			return 0.30
		&"sand_firm":
			return 0.42
		_:
			return 0.5


## Удар подвески на пробое. Берётся из суммарного хода: резкое изменение —
## это яма, а не езда.
func _check_suspension() -> void:
	var travel := 0.0
	for wheel: VehicleWheel in vehicle.wheels:
		travel += wheel.compression
	var delta := travel - _last_suspension
	_last_suspension = travel
	if delta > 0.55:
		var rng := RandomNumberGenerator.new()
		rng.seed = Time.get_ticks_usec()
		_thump.stream = _build_thump(rng, clampf(delta / 2.0, 0.2, 1.0))
		_thump.play()


# --- Синтез петель ----------------------------------------------------------


## Низ: частота вспышек и её вторая гармоника. Нарочно не синус — у поршневого
## мотора несимметричный импульс, и именно он даёт узнаваемую «тракторность».
func _build_rumble() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4001
	# Целое число периодов — иначе петля щёлкает на стыке.
	var cycles := 24
	var frames := int(round(float(Synth.RATE) * float(cycles) / REFERENCE_HZ))
	var buffer := PackedFloat32Array()
	buffer.resize(frames)
	for i: int in frames:
		var phase := float(i) / float(Synth.RATE) * REFERENCE_HZ
		var value := Synth.sine(phase) * 0.55
		value += Synth.sine(phase * 2.0) * 0.26
		value += Synth.saw(phase) * 0.16
		# Неравномерность вспышек: цилиндры не идеально одинаковые.
		value *= 1.0 + 0.12 * Synth.sine(phase / float(CYLINDERS))
		buffer[i] = value
	buffer = Synth.low_pass(buffer, 420.0)
	return Synth.to_stream(Synth.normalise(buffer, 0.85), true)


## Рык под нагрузкой: верхние гармоники и шум сгорания.
func _build_growl() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4002
	var cycles := 24
	var frames := int(round(float(Synth.RATE) * float(cycles) / REFERENCE_HZ))
	var buffer := PackedFloat32Array()
	buffer.resize(frames)
	for i: int in frames:
		var phase := float(i) / float(Synth.RATE) * REFERENCE_HZ
		var value := Synth.saw(phase) * 0.4
		value += Synth.square(phase * 3.0, 0.32) * 0.2
		value += Synth.sine(phase * 4.0) * 0.14
		buffer[i] = value
	var noise := Synth.pink_series(frames, rng)
	noise = Synth.band_pass(noise, 900.0, 0.8)
	for i: int in frames:
		buffer[i] += noise[i] * 0.3
	buffer = Synth.band_pass(buffer, 620.0, 0.55)
	_seam(buffer)
	return Synth.to_stream(Synth.normalise(buffer, 0.8), true)


## Впуск: свист воздуха, растёт с оборотами.
func _build_intake() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4003
	var frames := Synth.RATE
	var noise := Synth.pink_series(frames, rng)
	var shaped := Synth.band_pass(noise, 2400.0, 2.4)
	var whistle := PackedFloat32Array()
	whistle.resize(frames)
	for i: int in frames:
		var t := float(i) / float(Synth.RATE)
		whistle[i] = shaped[i] * 0.8 + Synth.sine(t * 2300.0) * 0.12
	_seam(whistle)
	return Synth.to_stream(Synth.normalise(whistle, 0.7), true)


## Качение: широкополосный шум с лёгкой периодикой протектора.
func _build_roll() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4004
	var frames := Synth.RATE
	var noise := Synth.pink_series(frames, rng)
	noise = Synth.low_pass(noise, 1400.0)
	for i: int in frames:
		var t := float(i) / float(Synth.RATE)
		noise[i] = noise[i] * (0.8 + 0.2 * Synth.sine(t * 34.0))
	_seam(noise)
	return Synth.to_stream(Synth.normalise(noise, 0.75), true)


## Набегающий поток: шум в верхней полосе, без периодики.
func _build_wind() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4005
	var frames := Synth.RATE
	var noise := Synth.pink_series(frames, rng)
	noise = Synth.high_pass(noise, 700.0)
	noise = Synth.band_pass(noise, 1600.0, 0.5)
	_seam(noise)
	return Synth.to_stream(Synth.normalise(noise, 0.7), true)


## Удар подвески о отбойник.
func _build_thump(rng: RandomNumberGenerator, force: float) -> AudioStreamWAV:
	var frames := int(0.22 * float(Synth.RATE))
	var buffer := PackedFloat32Array()
	buffer.resize(frames)
	var phase := 0.0
	for i: int in frames:
		var t := float(i) / float(Synth.RATE)
		var frequency := lerpf(96.0, 42.0, clampf(t / 0.05, 0.0, 1.0))
		phase += frequency / float(Synth.RATE)
		buffer[i] = (Synth.sine(phase) * 0.7 + Synth.white(rng) * 0.3) * exp(-t * 19.0)
	return Synth.to_stream(Synth.normalise(buffer, clampf(force, 0.2, 0.9)), false)


## Сводит конец петли с началом. Без этого на стыке слышен щелчок, а петля
## играет непрерывно — щелчок будет раз в секунду, и он невыносим.
static func _seam(buffer: PackedFloat32Array) -> void:
	var blend := mini(buffer.size() / 6, Synth.RATE / 10)
	for i: int in blend:
		var k := float(i) / float(blend)
		buffer[i] = lerpf(buffer[buffer.size() - blend + i], buffer[i], k)
