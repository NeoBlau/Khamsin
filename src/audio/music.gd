class_name Music
extends RefCounted
## Сочинение и сведение музыкальной фразы. На выходе — дорожка PCM, которую
## радио ставит в эфир.
##
## Логика устроена как маленький ансамбль: бурдон держит тонику, дарбука ведёт
## ритмический цикл, уд или ней играет мелодию по ступеням лада. Мелодия не
## случайный набор нот: она ходит шагами, тяготеет к опорным ступеням и
## заканчивает фразу на одной из них. Этого хватает, чтобы звучало как музыка,
## а не как генератор нот, — а больше от фонового радио и не требуется.


class Options:
	extends RefCounted
	var scale: StringName = &"bayati"
	var rhythm: StringName = &"maqsum"
	var tonic: float = -7.0  ## полутоны от ля первой октавы
	var tempo: float = 96.0  ## ударов в минуту
	var bars: int = 4
	var lead: StringName = &"oud"  ## oud, ney, qanun
	var drone: bool = true
	var percussion: bool = true
	var warmth: float = 0.5  ## 0 — сухо и близко, 1 — гулкий зал


## Длина фразы в секундах. Такт — восемь восьмых.
static func track_seconds(options: Options) -> float:
	var eighth := 30.0 / maxf(options.tempo, 20.0)
	return eighth * 8.0 * float(maxi(options.bars, 1))


static func render(seed_value: int, options: Options) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rate := Synth.RATE
	var eighth := 30.0 / maxf(options.tempo, 20.0)
	var bars := maxi(options.bars, 1)
	var total := int(track_seconds(options) * float(rate)) + rate
	var track := PackedFloat32Array()
	track.resize(total)

	if options.drone:
		_lay_drone(track, options, rate)
	if options.percussion:
		_lay_percussion(track, options, rng, eighth, bars, rate)
	_lay_melody(track, options, rng, eighth, bars, rate)

	var mixed := Synth.normalise(track, 0.82)
	if options.warmth > 0.01:
		mixed = Synth.delay(mixed, 0.11, 0.24 * options.warmth, 0.3 * options.warmth, rate)
		mixed = Synth.normalise(mixed, 0.85)
	return Synth.fade_edges(mixed, 0.04, rate)


# --- Бурдон -----------------------------------------------------------------


## Тоника и квинта тихим фоном на всю фразу. Без него мелодия висит в воздухе:
## ухо не слышит лада, пока нет опоры, по которой его определять.
static func _lay_drone(track: PackedFloat32Array, options: Options, rate: int) -> void:
	var frames := track.size()
	var root := Synth.note_hz(options.tonic - 12.0)
	var fifth := Synth.note_hz(options.tonic - 12.0 + 7.0)
	var drone := PackedFloat32Array()
	drone.resize(frames)
	for i: int in frames:
		var t := float(i) / float(rate)
		# Лёгкое биение между двумя голосами — живее, чем ровный тон.
		var wobble := 1.0 + 0.0016 * sin(t * TAU * 0.13)
		var value := Synth.sine(root * t) * 0.6
		value += Synth.sine(fifth * t * wobble) * 0.34
		value += Synth.saw(root * 0.5 * t) * 0.10
		drone[i] = value
	drone = Synth.low_pass(drone, 420.0, rate)
	Synth.mix_into(track, drone, 0, 0.26)


# --- Ударные ----------------------------------------------------------------


## Дум: низкий удар с падающей высотой. Кожа мембраны натянута, тон уходит вниз
## за десятую долю секунды — именно это падение и делает звук ударом, а не нотой.
static func darbuka_dum(seconds: float, rng: RandomNumberGenerator, rate: int = Synth.RATE) -> PackedFloat32Array:
	var frames := int(seconds * float(rate))
	var out := PackedFloat32Array()
	out.resize(frames)
	var phase := 0.0
	for i: int in frames:
		var t := float(i) / float(rate)
		var frequency := lerpf(128.0, 58.0, clampf(t / 0.09, 0.0, 1.0))
		phase += frequency / float(rate)
		var envelope := exp(-t * 17.0)
		out[i] = Synth.sine(phase) * envelope
	# Щелчок ладони поверх тона — без него дум звучит как гудок.
	var click := PackedFloat32Array()
	click.resize(mini(frames, int(0.012 * float(rate))))
	for i: int in click.size():
		click[i] = Synth.white(rng) * exp(-float(i) / float(rate) * 260.0)
	Synth.mix_into(out, Synth.low_pass(click, 2600.0, rate), 0, 0.5)
	return out


## Так: сухой щелчок по краю. Полосовой шум, очень короткий.
static func darbuka_tak(seconds: float, rng: RandomNumberGenerator, weak: bool,
		rate: int = Synth.RATE) -> PackedFloat32Array:
	var frames := int(seconds * float(rate))
	var raw := PackedFloat32Array()
	raw.resize(frames)
	var decay := 62.0 if weak else 38.0
	for i: int in frames:
		var t := float(i) / float(rate)
		raw[i] = Synth.white(rng) * exp(-t * decay)
	var shaped := Synth.band_pass(raw, 1850.0 if weak else 1420.0, 1.1, rate)
	var body := Synth.high_pass(raw, 900.0, rate)
	for i: int in frames:
		shaped[i] = shaped[i] * 0.8 + body[i] * 0.25
	return shaped


static func _lay_percussion(track: PackedFloat32Array, options: Options,
		rng: RandomNumberGenerator, eighth: float, bars: int, rate: int) -> void:
	var pattern := Maqam.rhythm(options.rhythm)
	var dum := darbuka_dum(0.34, rng, rate)
	for bar: int in bars:
		for step: int in pattern.length():
			var symbol := pattern[step]
			if symbol == ".":
				continue
			var at := int((float(bar * pattern.length() + step) * eighth) * float(rate))
			# Живая рука не попадает в сетку идеально, и это слышно как жизнь.
			at += int(rng.randfn(0.0, 0.006) * float(rate))
			var gain := 0.9 + rng.randf() * 0.12
			match symbol:
				"D":
					Synth.mix_into(track, dum, at, 0.58 * gain)
				"T":
					Synth.mix_into(track, darbuka_tak(0.13, rng, false, rate), at, 0.36 * gain)
				"k":
					Synth.mix_into(track, darbuka_tak(0.09, rng, true, rate), at, 0.2 * gain)


# --- Мелодия ----------------------------------------------------------------


## Одна нота ведущего инструмента.
static func lead_note(kind: StringName, frequency: float, seconds: float,
		rng: RandomNumberGenerator, rate: int = Synth.RATE) -> PackedFloat32Array:
	match kind:
		&"ney":
			return _ney(frequency, seconds, rng, rate)
		&"qanun":
			return _qanun(frequency, seconds, rng, rate)
		_:
			return _oud(frequency, seconds, rng, rate)


## Уд: щипок толстой струны, корпус глушит верх.
static func _oud(frequency: float, seconds: float, rng: RandomNumberGenerator,
		rate: int) -> PackedFloat32Array:
	var string := Synth.pluck(frequency, seconds, 0.030, rng, rate)
	var body := Synth.band_pass(string, frequency * 2.1, 1.8, rate)
	var out := PackedFloat32Array()
	out.resize(string.size())
	for i: int in string.size():
		var t := float(i) / float(rate)
		out[i] = (string[i] * 0.82 + body[i] * 0.45) * exp(-t * 1.6)
	return Synth.low_pass(out, 3400.0, rate)


## Канон: та же струна, но тоньше и звонче, с лёгким хором из трёх струн хора.
static func _qanun(frequency: float, seconds: float, rng: RandomNumberGenerator,
		rate: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * float(rate)))
	for detune: float in [0.0, -0.09, 0.11]:
		var voice := Synth.pluck(frequency * (1.0 + detune * 0.01), seconds, 0.016, rng, rate)
		Synth.mix_into(out, voice, 0, 0.42)
	for i: int in out.size():
		out[i] = out[i] * exp(-float(i) / float(rate) * 2.1)
	return Synth.high_pass(out, 180.0, rate)


## Ней: тростниковая флейта. Дыхание слышно не меньше тона — шумовая
## составляющая тут не дефект, а половина тембра.
static func _ney(frequency: float, seconds: float, rng: RandomNumberGenerator,
		rate: int) -> PackedFloat32Array:
	var frames := int(seconds * float(rate))
	var out := PackedFloat32Array()
	out.resize(frames)
	var breath := Synth.pink_series(frames, rng)
	var shaped := Synth.band_pass(breath, frequency * 1.4, 2.2, rate)
	var phase := 0.0
	for i: int in frames:
		var t := float(i) / float(rate)
		# Вибрато появляется не сразу: сначала нота устанавливается.
		var vibrato := 1.0 + 0.011 * sin(t * TAU * 5.2) * clampf((t - 0.12) * 4.0, 0.0, 1.0)
		phase += frequency * vibrato / float(rate)
		var tone := Synth.sine(phase) * 0.7 + Synth.sine(phase * 2.0) * 0.16
		var envelope := Synth.adsr(t, seconds, 0.16, 0.12, 0.85, 0.26)
		out[i] = (tone + shaped[i] * 0.55) * envelope
	return out


static func _lay_melody(track: PackedFloat32Array, options: Options,
		rng: RandomNumberGenerator, eighth: float, bars: int, rate: int) -> void:
	var resting := Maqam.resting_degrees(options.scale)
	var index: int = resting[rng.randi_range(0, resting.size() - 1)]
	var position := 0.0
	var total := float(bars) * 8.0 * eighth
	var phrase_end := total - eighth * 1.5
	while position < phrase_end:
		# Длительности: восьмая, четверть, реже половина. Ровные восьмые
		# подряд звучат как упражнение, а не как фраза.
		var roll := rng.randf()
		var length := eighth
		if roll > 0.78:
			length = eighth * 4.0
		elif roll > 0.42:
			length = eighth * 2.0
		length = minf(length, phrase_end - position + eighth)

		var frequency := Synth.note_hz(options.tonic + Maqam.degree(options.scale, index))
		var note := lead_note(options.lead, frequency, length * 1.15, rng, rate)
		Synth.mix_into(track, note, int(position * float(rate)), 0.5)

		# Украшение: короткая соседняя нота перед основной. В арабской мелодии
		# это норма, и без неё линия звучит выпрямленной.
		if rng.randf() > 0.72 and position > eighth:
			var grace_hz := Synth.note_hz(options.tonic + Maqam.degree(options.scale, index + 1))
			var grace := lead_note(options.lead, grace_hz, eighth * 0.4, rng, rate)
			Synth.mix_into(track, grace, int((position - eighth * 0.32) * float(rate)), 0.26)

		position += length
		index = _step(index, resting, rng)

	# Финальная нота фразы — обязательно опорная и длинная.
	var final_index: int = resting[0]
	var final_hz := Synth.note_hz(options.tonic + Maqam.degree(options.scale, final_index))
	var final_note := lead_note(options.lead, final_hz, eighth * 3.0, rng, rate)
	Synth.mix_into(track, final_note, int(phrase_end * float(rate)), 0.55)


## Следующая ступень. Ход преимущественно соседний, изредка скачок, и всегда с
## тяготением к опорным ступеням — на них мелодия задерживается.
static func _step(index: int, resting: Array[int], rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	var next := index
	if roll < 0.52:
		next = index + (1 if rng.randf() > 0.5 else -1)
	elif roll < 0.74:
		next = index + (2 if rng.randf() > 0.5 else -2)
	elif roll < 0.88:
		next = resting[rng.randi_range(0, resting.size() - 1)]
	else:
		next = index + (3 if rng.randf() > 0.5 else -3)
	return clampi(next, -3, 11)
