extends Node
## Автолоад Audio: единая точка, через которую играет всё.
##
## Держит радио, голос, окружение и щелчки интерфейса. Звук машины живёт не
## здесь, а на самой машине — он пространственный, и ему нужно ездить вместе
## с ней.
##
## Синтез голоса занимает сотни миллисекунд, поэтому реплики считаются в
## рабочем потоке. Диалог из-за этого начинает звучать не мгновенно, а через
## кадр-другой — это заметно меньше, чем просадка кадра на каждой реплике.

signal voice_started(speaker: StringName)

var radio: Radio

var _voice: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _ui: AudioStreamPlayer
var _voice_task: int = -1
var _voice_result: AudioStreamWAV = null
var _voice_speaker: StringName = &""
var _mutex := Mutex.new()
var _ambience_target: float = 0.0
var _cache: Dictionary = {}


func _ready() -> void:
	radio = Radio.new()
	add_child(radio)

	_voice = AudioStreamPlayer.new()
	_voice.bus = &"Voice"
	add_child(_voice)

	_ambience = AudioStreamPlayer.new()
	_ambience.bus = &"World"
	_ambience.stream = _build_ambience()
	_ambience.volume_db = -60.0
	add_child(_ambience)
	_ambience.play()

	_ui = AudioStreamPlayer.new()
	_ui.bus = &"UI"
	add_child(_ui)

	set_process(true)


## Та же история, что и у радио: синтез реплики идёт в потоке, и бросать его
## на произвол при выходе нельзя.
func _exit_tree() -> void:
	if _voice_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_voice_task)
		_voice_task = -1


func _process(delta: float) -> void:
	_collect_voice()
	var current := db_to_linear(_ambience.volume_db)
	var next := lerpf(current, _ambience_target, clampf(delta * 1.2, 0.0, 1.0))
	_ambience.volume_db = linear_to_db(clampf(next, 0.0005, 1.0))


# --- Окружение --------------------------------------------------------------


## Ветер снаружи. Буря — это не просто громче: спектр уходит вниз, потому что
## в воздухе песок, а не только воздух.
func set_wind(strength: float, sand: float) -> void:
	_ambience_target = clampf(strength * 0.5 + sand * 0.45, 0.0, 0.95)
	_ambience.pitch_scale = clampf(1.0 - sand * 0.35 + strength * 0.1, 0.4, 1.6)


# --- Голос ------------------------------------------------------------------


## Произносит реплику. Если у реплики есть записанный файл — играет его;
## синтез остаётся запасным путём, а не единственным.
func speak(speaker: StringName, text: String, recording: String = "") -> void:
	if recording != "" and ResourceLoader.exists(recording):
		var stream: AudioStream = load(recording)
		_voice.stream = stream
		_voice.play()
		voice_started.emit(speaker)
		radio.duck(0.3)
		return
	if text.strip_edges().is_empty():
		return
	var key := "%s|%s" % [speaker, text]
	if _cache.has(key):
		_play_voice(_cache[key], speaker)
		return
	if _voice_task >= 0:
		return
	_voice_speaker = speaker
	var plan := {
		"speaker": speaker,
		"text": text,
		"seed": Rng.hash_string(key),
		"key": key,
	}
	_voice_task = WorkerThreadPool.add_task(_render_voice.bind(plan), true, "voice line")


## То же, что speak, но голос выводится из имени, когда у реплики его нет.
func speak_as(voice_id: StringName, speaker_name: String, text: String) -> void:
	if text.strip_edges().is_empty():
		return
	var key := "%s|%s|%s" % [voice_id, speaker_name, text]
	if _cache.has(key):
		_play_voice(_cache[key], voice_id)
		return
	if _voice_task >= 0:
		# Предыдущая реплика ещё считается. Реплики сменяются кнопкой, так что
		# пропустить одну — меньшее зло, чем встать в очередь и заговорить
		# поверх следующей.
		return
	_voice_speaker = voice_id
	_voice_task = WorkerThreadPool.add_task(
		_render_voice_as.bind({
			"voice": voice_id,
			"name": speaker_name,
			"text": text,
			"seed": Rng.hash_string(key),
		}), true, "voice line")


func _render_voice_as(plan: Dictionary) -> void:
	var profile := Voice.resolve(plan["voice"], plan["name"])
	var buffer := Voice.render_line(plan["text"], profile, plan["seed"])
	var stream := Synth.to_stream(buffer, false)
	_mutex.lock()
	_voice_result = stream
	_mutex.unlock()


func stop_voice() -> void:
	_voice.stop()
	radio.duck(1.0)


func _render_voice(plan: Dictionary) -> void:
	var profile := Voice.profile(plan["speaker"])
	var buffer := Voice.render_line(plan["text"], profile, plan["seed"])
	var stream := Synth.to_stream(buffer, false)
	_mutex.lock()
	_voice_result = stream
	_mutex.unlock()


func _collect_voice() -> void:
	if _voice_task < 0:
		return
	if not WorkerThreadPool.is_task_completed(_voice_task):
		return
	WorkerThreadPool.wait_for_task_completion(_voice_task)
	_voice_task = -1
	_mutex.lock()
	var stream := _voice_result
	_voice_result = null
	_mutex.unlock()
	if stream != null:
		_play_voice(stream, _voice_speaker)


func _play_voice(stream: AudioStreamWAV, speaker: StringName) -> void:
	# Кеш не даёт синтезировать одну и ту же реплику дважды: в диалогах к ним
	# возвращаются, а считать каждый раз заново — это лишние полсекунды.
	if _cache.size() > 64:
		_cache.clear()
	_voice.stream = stream
	_voice.play()
	voice_started.emit(speaker)
	radio.duck(0.3)
	if not _voice.finished.is_connected(_on_voice_done):
		_voice.finished.connect(_on_voice_done)


func _on_voice_done() -> void:
	radio.duck(1.0)


func cache_voice(key: String, stream: AudioStreamWAV) -> void:
	_cache[key] = stream


# --- Интерфейс --------------------------------------------------------------


func click(kind: StringName = &"tap") -> void:
	var key := "ui:%s" % kind
	if not _cache.has(key):
		_cache[key] = _build_click(kind)
	_ui.stream = _cache[key]
	_ui.play()


func _build_click(kind: StringName) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = Rng.hash_string(String(kind))
	var frames := int(0.06 * float(Synth.RATE))
	var buffer := PackedFloat32Array()
	buffer.resize(frames)
	var base := 900.0
	var decay := 60.0
	match kind:
		&"accept":
			base = 660.0
			decay = 26.0
		&"deny":
			base = 220.0
			decay = 22.0
		&"toast":
			base = 1180.0
			decay = 34.0
	for i: int in frames:
		var t := float(i) / float(Synth.RATE)
		var value := Synth.sine(base * t) * 0.6 + Synth.sine(base * 1.5 * t) * 0.2
		value += Synth.white(rng) * 0.12
		buffer[i] = value * exp(-t * decay)
	return Synth.to_stream(Synth.normalise(buffer, 0.55), false)


# --- Синтез окружения -------------------------------------------------------


func _build_ambience() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7007
	var frames := Synth.RATE * 4
	var noise := Synth.pink_series(frames, rng)
	noise = Synth.low_pass(noise, 1100.0)
	# Порывы: ветер в пустыне не ровный гул, он дышит.
	for i: int in frames:
		var t := float(i) / float(Synth.RATE)
		var gust := 0.55 + 0.45 * (0.6 * sin(t * TAU * 0.09) + 0.4 * sin(t * TAU * 0.037 + 1.7))
		noise[i] = noise[i] * gust
	var blend := Synth.RATE / 2
	for i: int in blend:
		var k := float(i) / float(blend)
		noise[i] = lerpf(noise[frames - blend + i], noise[i], k)
	return Synth.to_stream(Synth.normalise(noise, 0.7), true)
