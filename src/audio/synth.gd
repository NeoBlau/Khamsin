class_name Synth
extends RefCounted
## Синтез звука в коде. В проекте нет ни одного звукового файла, и это то же
## решение, что и с геометрией: звук выводится из параметров, а не лежит
## записанным. Плюсы конкретные — ничего не весит, ничего не заимствовано,
## двигатель звучит от оборотов, а не от подобранного семпла, и радиостанцию
## можно сгенерировать на лету из сида.
##
## Всё ниже — чистые функции над PackedFloat32Array в диапазоне [-1, 1].
## Превращение в поток движка — единственное место, которое знает про Godot.

const RATE := 22050
const TAU_F := TAU


# --- Огибающие --------------------------------------------------------------


## ADSR в долях от длины. Возвращает множитель громкости на кадре.
static func adsr(position: float, length: float, attack: float, decay: float,
		sustain: float, release: float) -> float:
	if length <= 0.0:
		return 0.0
	var t := position / length
	if t < attack:
		return t / maxf(attack, 0.00001)
	if t < attack + decay:
		var k := (t - attack) / maxf(decay, 0.00001)
		return lerpf(1.0, sustain, k)
	if t < 1.0 - release:
		return sustain
	var tail := (1.0 - t) / maxf(release, 0.00001)
	return sustain * clampf(tail, 0.0, 1.0)


# --- Осцилляторы ------------------------------------------------------------


static func sine(phase: float) -> float:
	return sin(phase * TAU_F)


static func saw(phase: float) -> float:
	return fposmod(phase, 1.0) * 2.0 - 1.0


static func square(phase: float, duty: float = 0.5) -> float:
	return 1.0 if fposmod(phase, 1.0) < duty else -1.0


static func triangle(phase: float) -> float:
	var p := fposmod(phase, 1.0)
	return (1.0 - absf(p * 4.0 - 2.0)) if p < 0.75 else (p - 1.0) * 4.0


# --- Шум --------------------------------------------------------------------


## Белый шум из детерминированного потока: один и тот же сид даёт один и тот же
## порыв ветра. Для отладки это важнее, чем кажется.
static func white(rng: RandomNumberGenerator) -> float:
	return rng.randf() * 2.0 - 1.0


## Розовый шум приближением Восса — три полосы с разной скоростью обновления.
## Звучит как ветер и как помехи в эфире, белый для этого слишком резкий.
static func pink_series(frames: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	for i: int in frames:
		var w := white(rng)
		b0 = 0.99765 * b0 + w * 0.0990460
		b1 = 0.96300 * b1 + w * 0.2965164
		b2 = 0.57000 * b2 + w * 1.0526913
		out[i] = clampf((b0 + b1 + b2 + w * 0.1848) * 0.22, -1.0, 1.0)
	return out


# --- Фильтры ----------------------------------------------------------------


## Однополюсный низкочастотный. cutoff в герцах.
static func low_pass(source: PackedFloat32Array, cutoff: float, rate: int = RATE) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(source.size())
	var dt := 1.0 / float(rate)
	var rc := 1.0 / maxf(TAU_F * cutoff, 0.0001)
	var alpha := dt / (rc + dt)
	var value := 0.0
	for i: int in source.size():
		value += alpha * (source[i] - value)
		out[i] = value
	return out


static func high_pass(source: PackedFloat32Array, cutoff: float, rate: int = RATE) -> PackedFloat32Array:
	var low := low_pass(source, cutoff, rate)
	var out := PackedFloat32Array()
	out.resize(source.size())
	for i: int in source.size():
		out[i] = source[i] - low[i]
	return out


## Резонансный полосовой на биквадре. Нужен для формант голоса и для корпуса
## уда: без резонанса струна звучит как пищалка, а не как инструмент.
static func band_pass(source: PackedFloat32Array, centre: float, q: float,
		rate: int = RATE) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(source.size())
	var w0 := TAU_F * centre / float(rate)
	var alpha := sin(w0) / (2.0 * maxf(q, 0.05))
	var b0 := alpha
	var b1 := 0.0
	var b2 := -alpha
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cos(w0)
	var a2 := 1.0 - alpha
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i: int in source.size():
		var x := source[i]
		var y := (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		out[i] = y
	return out


# --- Струна -----------------------------------------------------------------


## Карплюс-Стронг: щипок струны. Короткий шумовой буфер длиной в период,
## прогоняемый по кругу с усреднением. Для уда и канона это ровно то, что надо,
## и стоит копейки по сравнению с честной физической моделью.
static func pluck(frequency: float, seconds: float, damping: float,
		rng: RandomNumberGenerator, rate: int = RATE) -> PackedFloat32Array:
	var frames := int(seconds * float(rate))
	var out := PackedFloat32Array()
	out.resize(frames)
	if frequency <= 0.0 or frames <= 0:
		return out
	var period := maxi(2, int(round(float(rate) / frequency)))
	var buffer := PackedFloat32Array()
	buffer.resize(period)
	for i: int in period:
		buffer[i] = white(rng)
	# Мягкий старт: чистый шум даёт слишком стеклянную атаку.
	for _pass: int in 2:
		for i: int in period:
			buffer[i] = (buffer[i] + buffer[(i + 1) % period]) * 0.5
	var index := 0
	var keep := clampf(1.0 - damping, 0.80, 0.9995)
	for i: int in frames:
		var next := (index + 1) % period
		var value := (buffer[index] + buffer[next]) * 0.5 * keep
		out[i] = buffer[index]
		buffer[index] = value
		index = next
	return out


# --- Пространство -----------------------------------------------------------


## Задержка с обратной связью. Дешёвая замена реверберации: комната, ангар,
## мраморный холл особняка — всё это разная длина и разное затухание.
static func delay(source: PackedFloat32Array, seconds: float, feedback: float,
		mix: float, rate: int = RATE) -> PackedFloat32Array:
	var frames := source.size()
	var out := PackedFloat32Array()
	out.resize(frames)
	var offset := maxi(1, int(seconds * float(rate)))
	for i: int in frames:
		var echo := out[i - offset] if i >= offset else 0.0
		out[i] = source[i] + echo * clampf(feedback, 0.0, 0.95)
	for i: int in frames:
		out[i] = lerpf(source[i], out[i], clampf(mix, 0.0, 1.0))
	return out


# --- Сведение ---------------------------------------------------------------


static func mix_into(target: PackedFloat32Array, source: PackedFloat32Array,
		at_frame: int, gain: float) -> void:
	var count := source.size()
	for i: int in count:
		var index := at_frame + i
		if index < 0 or index >= target.size():
			continue
		target[index] += source[i] * gain


## Нормирует по пику с запасом. Клиппинг в процедурном звуке — обычное дело:
## складываются десятки голосов, и пик заранее неизвестен.
static func normalise(buffer: PackedFloat32Array, peak: float = 0.89) -> PackedFloat32Array:
	var maximum := 0.0
	for v: float in buffer:
		maximum = maxf(maximum, absf(v))
	if maximum <= 0.00001:
		return buffer
	var gain := peak / maximum
	for i: int in buffer.size():
		buffer[i] = buffer[i] * gain
	return buffer


## Плавные края. Без них стык буферов щёлкает, и это слышно сразу.
static func fade_edges(buffer: PackedFloat32Array, seconds: float, rate: int = RATE) -> PackedFloat32Array:
	var count := mini(int(seconds * float(rate)), buffer.size() / 2)
	for i: int in count:
		var k := float(i) / float(maxi(count, 1))
		buffer[i] = buffer[i] * k
		buffer[buffer.size() - 1 - i] = buffer[buffer.size() - 1 - i] * k
	return buffer


# --- Выход в движок ---------------------------------------------------------


## Превращает дорожку в поток. Единственное место, знающее про формат Godot.
static func to_stream(buffer: PackedFloat32Array, looping: bool = false,
		rate: int = RATE) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(buffer.size() * 2)
	for i: int in buffer.size():
		var sample := int(round(clampf(buffer[i], -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 2, sample)
	stream.data = bytes
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = buffer.size()
	return stream


## Длина потока в секундах. Отдельной функцией, потому что считать её из
## размера данных руками — верный способ ошибиться вдвое на 16 битах.
static func stream_seconds(stream: AudioStreamWAV) -> float:
	if stream == null or stream.mix_rate <= 0:
		return 0.0
	var bytes_per_frame := 2 * (2 if stream.stereo else 1)
	return float(stream.data.size()) / float(bytes_per_frame) / float(stream.mix_rate)


# --- Ноты -------------------------------------------------------------------


## Частота по номеру полутона относительно ля первой октавы. Дробный номер
## допустим и нужен: в арабских ладах есть четвертитоновые ступени, и без них
## хиджаз звучит как европейский минор.
static func note_hz(semitones: float) -> float:
	return 440.0 * pow(2.0, semitones / 12.0)
