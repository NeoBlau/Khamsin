class_name Voice
extends RefCounted
## Голос: формантный синтез речи без слов.
##
## Настоящей озвучки в игре нет — записать её я не могу. Вместо неё каждая
## реплика звучит собственным голосом говорящего: высота, темп, хрипота и
## набор формант у Надии, Юсуфа и Дяди Вали разные, и по голосу их слышно
## раньше, чем прочитаешь имя.
##
## Работает это так. Гласную ухо опознаёт по двум-трём резонансам голосового
## тракта — формантам. Берём импульсы голосовых связок, прогоняем через
## полосовые фильтры на частотах формант — получаем «а», «и», «у». Слоги
## складываются в реплику, ритм и интонация берутся из самого текста: длина
## слова, запятая, вопросительный знак.
##
## Слоты под настоящие записи оставлены: если реплике задан звуковой файл, он
## и проигрывается, а синтез остаётся запасным путём.


## Форманты гласных в герцах: первая, вторая, третья.
const VOWELS := {
	&"a": [730.0, 1090.0, 2440.0],
	&"e": [530.0, 1840.0, 2480.0],
	&"i": [270.0, 2290.0, 3010.0],
	&"o": [570.0, 840.0, 2410.0],
	&"u": [300.0, 870.0, 2240.0],
	# Арабские эмфатические: язык оттянут назад, вторая форманта падает.
	&"aa": [650.0, 1000.0, 2200.0],
	&"ayn": [600.0, 1150.0, 2100.0],
}


class Profile:
	extends RefCounted
	var pitch: float = 120.0  ## основной тон в герцах
	var pitch_range: float = 0.16  ## насколько гуляет интонация
	var speed: float = 1.0  ## слогов в секунду относительно базовых шести
	var roughness: float = 0.12  ## примесь шума в связках
	var breath: float = 0.08  ## придыхание
	var vowels: Array[StringName] = [&"a", &"e", &"i", &"o", &"u"]
	var formant_shift: float = 1.0  ## длина тракта: выше — «меньше» голова
	var warmth: float = 0.15

	func duplicated() -> Profile:
		var copy := Profile.new()
		copy.pitch = pitch
		copy.pitch_range = pitch_range
		copy.speed = speed
		copy.roughness = roughness
		copy.breath = breath
		copy.vowels = vowels.duplicate()
		copy.formant_shift = formant_shift
		copy.warmth = warmth
		return copy


## Готовые голоса. Заводятся по идентификатору говорящего из data/story.
static func profile(id: StringName) -> Profile:
	var p := Profile.new()
	match id:
		&"nadia":  # диспетчер: быстро, ровно, чуть устало
			p.pitch = 196.0
			p.pitch_range = 0.12
			p.speed = 1.22
			p.roughness = 0.07
			p.formant_shift = 1.14
		&"yusuf":  # дядя-механик: низко, неторопливо, с хрипотцой
			p.pitch = 104.0
			p.pitch_range = 0.10
			p.speed = 0.84
			p.roughness = 0.24
			p.breath = 0.14
			p.formant_shift = 0.94
		&"valya":  # Дядя Валя Вилсаком: тараторит, голос вверх на каждой фразе
			p.pitch = 148.0
			p.pitch_range = 0.31
			p.speed = 1.48
			p.roughness = 0.10
			p.breath = 0.05
			p.formant_shift = 1.06
			p.warmth = 0.28
		&"official":  # человек из правительства: ровно, без интонаций вовсе
			p.pitch = 118.0
			p.pitch_range = 0.03
			p.speed = 0.92
			p.roughness = 0.05
			p.formant_shift = 0.99
		&"radio_host":
			p.pitch = 132.0
			p.pitch_range = 0.26
			p.speed = 1.16
			p.roughness = 0.09
			p.vowels = [&"a", &"aa", &"i", &"ayn", &"u"]
			p.warmth = 0.32
		&"radio_host_woman":
			p.pitch = 214.0
			p.pitch_range = 0.22
			p.speed = 1.08
			p.roughness = 0.05
			p.vowels = [&"a", &"aa", &"i", &"ayn", &"e"]
			p.warmth = 0.32
		&"camel":  # верблюд: не речь, но по той же механике
			p.pitch = 62.0
			p.pitch_range = 0.42
			p.speed = 0.5
			p.roughness = 0.62
			p.breath = 0.5
			p.vowels = [&"o", &"aa"]
			p.formant_shift = 0.68
		_:
			pass
	return p


## Голос для реплики. Если у узла диалога задан voice — берём готовый профиль,
## иначе выводим его из имени говорящего. Второе важнее, чем кажется: имён в
## сюжете десятки, расписывать каждому профиль руками никто не станет, а
## безымянный «инженер на Точке 7» всё равно должен звучать не как Надия.
static func resolve(voice_id: StringName, speaker_name: String) -> Profile:
	if voice_id != &"":
		return profile(voice_id)
	return derived(speaker_name)


## Устойчивый голос из имени. Одно и то же имя всегда даёт один и тот же голос,
## поэтому персонаж не меняет тембр между разговорами.
static func derived(speaker_name: String) -> Profile:
	var p := Profile.new()
	var h := absi(speaker_name.hash())
	# Женское имя или должность — выше. Грубая эвристика, но она ловит
	# большинство русских женских имён и не требует таблицы.
	var lower := speaker_name.to_lower()
	var feminine := lower.ends_with("а") or lower.ends_with("я") or lower.contains("надия")
	var base := 188.0 if feminine else 116.0
	p.pitch = base * (1.0 + (float(h % 100) / 100.0 - 0.5) * 0.30)
	p.pitch_range = 0.08 + float((h / 100) % 100) / 100.0 * 0.22
	p.speed = 0.82 + float((h / 10000) % 100) / 100.0 * 0.5
	p.roughness = 0.04 + float((h / 1000000) % 100) / 100.0 * 0.22
	p.breath = 0.04 + float((h / 7) % 50) / 50.0 * 0.12
	p.formant_shift = (1.12 if feminine else 0.95) * (1.0 + (float((h / 13) % 100) / 100.0 - 0.5) * 0.12)
	return p


## Один слог. Импульсы связок, прогнанные через форманты гласной.
static func syllable(profile_data: Profile, vowel: StringName, seconds: float,
		pitch_hz: float, rng: RandomNumberGenerator, rate: int = Synth.RATE) -> PackedFloat32Array:
	var frames := int(seconds * float(rate))
	if frames <= 0:
		return PackedFloat32Array()
	var source := PackedFloat32Array()
	source.resize(frames)
	var phase := 0.0
	for i: int in frames:
		var t := float(i) / float(rate)
		# Интонация внутри слога: голос слегка ведёт вниз, как у живого.
		var glide := 1.0 - 0.06 * (t / maxf(seconds, 0.001))
		phase += pitch_hz * glide / float(rate)
		# Импульс связок: пила даёт богатый спектр, который форманты и лепят.
		var pulse := Synth.saw(phase)
		pulse = pulse * (1.0 - profile_data.roughness) + Synth.white(rng) * profile_data.roughness
		source[i] = pulse
	var formants: Array = VOWELS.get(vowel, VOWELS[&"a"])
	var out := PackedFloat32Array()
	out.resize(frames)
	var weights := [0.62, 0.38, 0.18]
	for k: int in 3:
		var centre := float(formants[k]) * profile_data.formant_shift
		var shaped := Synth.band_pass(source, centre, 5.5 - float(k) * 1.2, rate)
		for i: int in frames:
			out[i] += shaped[i] * float(weights[k])
	if profile_data.breath > 0.001:
		var air := Synth.pink_series(frames, rng)
		air = Synth.high_pass(air, 2200.0, rate)
		for i: int in frames:
			out[i] += air[i] * profile_data.breath
	for i: int in frames:
		out[i] = out[i] * Synth.adsr(float(i) / float(rate), seconds, 0.18, 0.15, 0.8, 0.3)
	return out


## Реплика целиком. Ритм берётся из текста: слово даёт слоги, запятая — паузу,
## вопросительный знак — подъём тона к концу. Слов никто не разберёт, но
## интонация читается, и этого достаточно, чтобы фраза звучала фразой.
static func render_line(text: String, profile_data: Profile, seed_value: int,
		rate: int = Synth.RATE) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var plan := plan_line(text, profile_data)
	if plan.is_empty():
		return PackedFloat32Array()
	var total := 0.0
	for entry: Dictionary in plan:
		total = maxf(total, float(entry["at"]) + float(entry["length"]))
	var track := PackedFloat32Array()
	track.resize(int((total + 0.2) * float(rate)))
	for entry: Dictionary in plan:
		var blip := syllable(
			profile_data,
			entry["vowel"],
			entry["length"],
			entry["pitch"],
			rng,
			rate,
		)
		Synth.mix_into(track, blip, int(float(entry["at"]) * float(rate)), float(entry["gain"]))
	var mixed := Synth.normalise(track, 0.8)
	if profile_data.warmth > 0.01:
		mixed = Synth.delay(mixed, 0.055, 0.2 * profile_data.warmth, 0.28 * profile_data.warmth, rate)
	return Synth.fade_edges(Synth.normalise(mixed, 0.82), 0.02, rate)


## Разбор текста в расписание слогов. Вынесено отдельно и без звука, чтобы
## интонацию можно было проверить тестом, не слушая.
static func plan_line(text: String, profile_data: Profile) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var stripped := text.strip_edges()
	if stripped.is_empty():
		return plan
	var question := stripped.ends_with("?")
	var exclaim := stripped.ends_with("!")
	var base := 0.135 / maxf(profile_data.speed, 0.2)
	var at := 0.0
	var index := 0
	var words := stripped.split(" ", false)
	var total_syllables := 0
	for word: String in words:
		total_syllables += _syllables_in(word)
	var spoken := 0
	for word: String in words:
		var count := _syllables_in(word)
		for s: int in count:
			var progress := float(spoken) / float(maxi(total_syllables - 1, 1))
			# Интонация фразы: вопрос ведёт вверх к концу, восклицание
			# начинается высоко, обычная фраза спокойно оседает.
			var contour := -0.22 * progress
			if question:
				contour = -0.05 + 0.55 * pow(progress, 2.2)
			elif exclaim:
				contour = 0.30 - 0.34 * progress
			# Ударение: первый слог слова слышнее и чуть выше.
			var stress := 1.0 if s == 0 else 0.74
			var wobble := sin(float(index) * 2.399) * 0.5
			var pitch := profile_data.pitch * (1.0 + (contour + wobble * profile_data.pitch_range) * 0.5)
			var length := base * (1.25 if s == 0 else 1.0)
			plan.append({
				"at": at,
				"length": length,
				"pitch": maxf(pitch, 40.0),
				"gain": 0.55 * stress,
				"vowel": profile_data.vowels[index % profile_data.vowels.size()],
			})
			at += length * 0.92
			index += 1
			spoken += 1
		# Пауза между словами, и заметно длиннее — на знаках препинания.
		at += base * 0.35
		var tail := word.substr(word.length() - 1, 1)
		if tail == "," or tail == ":" or tail == ";" or tail == "—":
			at += base * 1.1
		elif tail == "." or tail == "!" or tail == "?":
			at += base * 1.6
	return plan


## Слогов в слове ≈ числу гласных. Грубо, но нам нужен ритм, а не разбор.
static func _syllables_in(word: String) -> int:
	const VOWEL_LETTERS := "аеёиоуыэюяaeiouy"
	var count := 0
	for i: int in word.length():
		if VOWEL_LETTERS.contains(word.substr(i, 1).to_lower()):
			count += 1
	return maxi(count, 1)
