class_name Radio
extends Node
## Радиоприёмник в кабине.
##
## Эфир не плейлист: станция собирает очередной кусок в момент выхода в эфир —
## лад, ритм, темп и ведущий берутся из правил станции, а не из списка файлов.
## Синтез идёт в рабочем потоке, пока играет текущий кусок, поэтому переход
## между треками не роняет кадр.
##
## Приём зависит от расстояния до передатчика. Пиратскую волну слышно только
## в двадцати километрах от её сарая и только ночью — найти её это отдельная
## находка, а не пункт меню.

signal station_changed(station: RadioStation)
signal segment_started(label: String)

const DATA_PATH := "res://data/audio/radio.json"
## Сколько кусков держим наготове. Два: играющий и следующий.
const QUEUE_DEPTH := 2

var stations: Array[RadioStation] = []
var enabled: bool = false
var station_index: int = 0
var reception: float = 1.0

var _player: AudioStreamPlayer
var _static_player: AudioStreamPlayer
var _queue: Array[Dictionary] = []
var _building: bool = false
var _build_result: Dictionary = {}
var _mutex := Mutex.new()
var _task_id: int = -1
var _rng := RandomNumberGenerator.new()
var _listener: Vector2 = Vector2.ZERO
var _hour: float = 12.0
var _current_label: String = ""
var _duck: float = 1.0


func _ready() -> void:
	name = "Radio"
	_rng.seed = Rng.hash_string("radio")
	load_stations()
	_player = AudioStreamPlayer.new()
	_player.bus = &"Radio"
	_player.finished.connect(_advance)
	add_child(_player)
	_static_player = AudioStreamPlayer.new()
	_static_player.bus = &"Radio"
	_static_player.stream = _make_static()
	add_child(_static_player)
	set_process(true)


## Выход из игры не должен заставать рабочий поток врасплох. Задача держит
## связанный Callable на этом узле: если узел освободить, пока она считает,
## поток обратится к уже исчезнувшему мьютексу. Дожидаемся её здесь — это
## доли секунды, зато детерминированно.
func _exit_tree() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	_building = false


func load_stations() -> void:
	stations.clear()
	var text := FileAccess.get_file_as_string(DATA_PATH)
	if text.is_empty():
		push_warning("Радио: %s не читается" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Радио: %s не разобран" % DATA_PATH)
		return
	for entry: Dictionary in (parsed as Dictionary).get("stations", []):
		stations.append(_station_from(entry))


func _station_from(entry: Dictionary) -> RadioStation:
	var station := RadioStation.new()
	station.id = StringName(entry.get("id", "station"))
	station.name = entry.get("name", "Станция")
	station.frequency = float(entry.get("frequency", 88.0))
	station.scales = _names(entry.get("scales", ["bayati"]))
	station.rhythms = _names(entry.get("rhythms", ["maqsum"]))
	station.leads = _names(entry.get("leads", ["oud"]))
	var tempo: Array = entry.get("tempo", [80, 100])
	station.tempo_range = Vector2(float(tempo[0]), float(tempo[1]))
	station.host = StringName(entry.get("host", "radio_host"))
	station.warmth = float(entry.get("warmth", 0.35))
	station.talk_chance = float(entry.get("talk_chance", 0.3))
	station.advert_chance = float(entry.get("advert_chance", 0.2))
	station.range_km = float(entry.get("range_km", 1000.0))
	station.requires_flag = StringName(entry.get("requires_flag", ""))
	var hours: Array = entry.get("hours", [])
	if hours.size() == 2:
		station.hours = Vector2(float(hours[0]), float(hours[1]))
	var transmitter: Array = entry.get("transmitter", [])
	if transmitter.size() == 2:
		station.transmitter = Vector2(float(transmitter[0]), float(transmitter[1]))
	station.talk_lines = PackedStringArray(entry.get("talk", []))
	station.advert_lines = PackedStringArray(entry.get("advert", []))
	station.station_id_lines = PackedStringArray(entry.get("station_id", []))
	return station


func _names(source: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for item: Variant in source:
		out.append(StringName(item))
	return out


# --- Управление -------------------------------------------------------------


func current() -> RadioStation:
	if stations.is_empty():
		return null
	return stations[posmod(station_index, stations.size())]


## Станции, которые сейчас вообще можно поймать: в эфире по времени и открыты
## по сюжету. Крутилка ходит только по ним — ловить тишину неинтересно.
func available() -> Array[RadioStation]:
	var out: Array[RadioStation] = []
	for station: RadioStation in stations:
		if not station.on_air_at(_hour):
			continue
		if station.requires_flag != &"" and not bool(GameState.flag(station.requires_flag)):
			continue
		out.append(station)
	return out


func toggle() -> void:
	set_enabled(not enabled)


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	if enabled:
		_queue.clear()
		_request_segment()
		_advance()
	else:
		_player.stop()
		_static_player.stop()
		_current_label = ""


func step_station(direction: int) -> void:
	var pool := available()
	if pool.is_empty():
		return
	var here := current()
	var at := pool.find(here)
	at = posmod(at + direction, pool.size()) if at >= 0 else 0
	var target := pool[at]
	station_index = stations.find(target)
	_queue.clear()
	_player.stop()
	_current_label = ""
	if enabled:
		_request_segment()
		_advance()
	station_changed.emit(target)


## Строка для приборной панели: «88.3 Хамсин FM — хиджаз, уд».
func now_playing() -> String:
	var station := current()
	if station == null or not enabled:
		return ""
	if reception < 0.25:
		return "%.1f  помехи" % station.frequency
	if _current_label.is_empty():
		return "%.1f  %s" % [station.frequency, station.name]
	return "%.1f  %s — %s" % [station.frequency, station.name, _current_label]


## Приглушение на время разговора: диалог важнее музыки.
func duck(amount: float) -> void:
	_duck = clampf(amount, 0.0, 1.0)


func listen_from(position: Vector2, hour: float) -> void:
	_listener = position
	_hour = hour


# --- Эфир -------------------------------------------------------------------


func _process(_delta: float) -> void:
	_collect_built()
	if not enabled:
		return
	var station := current()
	if station == null:
		return
	# Станция ушла из эфира по времени — крутим дальше сама.
	if not station.on_air_at(_hour):
		step_station(1)
		return
	reception = station.reception(_listener)
	var music_db := linear_to_db(clampf(reception * _duck, 0.0001, 1.0))
	_player.volume_db = music_db
	var noise := clampf(1.0 - reception, 0.0, 1.0)
	if noise > 0.02:
		if not _static_player.playing:
			_static_player.play()
		_static_player.volume_db = linear_to_db(clampf(noise * 0.55 * _duck, 0.0001, 1.0))
	elif _static_player.playing:
		_static_player.stop()
	if _queue.size() < QUEUE_DEPTH:
		_request_segment()


func _advance() -> void:
	if not enabled:
		return
	if _queue.is_empty():
		# Следующий кусок ещё синтезируется: подождём кадр, эфир пока шипит.
		if not _static_player.playing:
			_static_player.play()
			_static_player.volume_db = linear_to_db(0.18)
		return
	var segment: Dictionary = _queue.pop_front()
	_player.stream = segment["stream"]
	_current_label = segment["label"]
	_player.play()
	segment_started.emit(_current_label)
	_request_segment()


func _request_segment() -> void:
	if _building or stations.is_empty():
		return
	var station := current()
	if station == null:
		return
	_building = true
	var plan := _plan_segment(station)
	_task_id = WorkerThreadPool.add_task(_build_segment.bind(plan), true, "radio segment")


## Что именно выйдет в эфир следующим. Решение принимается в главном потоке —
## в рабочий уходит только счёт, без обращений к состоянию игры.
func _plan_segment(station: RadioStation) -> Dictionary:
	var roll := _rng.randf()
	var kind := &"music"
	if roll < station.talk_chance * 0.4:
		kind = &"station_id"
	elif roll < station.talk_chance:
		kind = &"talk"
	elif roll < station.talk_chance + station.advert_chance:
		kind = &"advert"
	var plan := {
		"kind": kind,
		"seed": _rng.randi(),
		"host": station.host,
		"warmth": station.warmth,
	}
	match kind:
		&"talk", &"station_id", &"advert":
			var pool := station.talk_lines
			if kind == &"advert":
				pool = station.advert_lines
			elif kind == &"station_id":
				pool = station.station_id_lines
			if pool.is_empty():
				plan["kind"] = &"music"
			else:
				plan["text"] = pool[_rng.randi_range(0, pool.size() - 1)]
	if plan["kind"] == &"music":
		plan["scale"] = station.pick_scale(_rng)
		plan["rhythm"] = station.pick_rhythm(_rng)
		plan["lead"] = station.pick_lead(_rng)
		plan["tempo"] = station.pick_tempo(_rng)
		plan["bars"] = _rng.randi_range(4, 7)
	return plan


## Тело рабочего потока. Трогает только чистый синтез — ни сцены, ни автолоадов.
func _build_segment(plan: Dictionary) -> void:
	var buffer := PackedFloat32Array()
	var label := ""
	match plan["kind"]:
		&"music":
			var options := Music.Options.new()
			options.scale = plan["scale"]
			options.rhythm = plan["rhythm"]
			options.lead = plan["lead"]
			options.tempo = plan["tempo"]
			options.bars = plan["bars"]
			options.warmth = plan["warmth"]
			buffer = Music.render(plan["seed"], options)
			label = "%s, %s" % [
				Maqam.scale_name(plan["scale"]),
				_lead_name(plan["lead"]),
			]
		_:
			var profile := Voice.profile(plan["host"])
			buffer = Voice.render_line(plan["text"], profile, plan["seed"])
			label = "ведущий" if plan["kind"] != &"advert" else "реклама"
	_mutex.lock()
	_build_result = {"stream": Synth.to_stream(buffer, false), "label": label}
	_mutex.unlock()


func _collect_built() -> void:
	if not _building:
		return
	if _task_id >= 0 and not WorkerThreadPool.is_task_completed(_task_id):
		return
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	_mutex.lock()
	var result := _build_result.duplicate()
	_build_result = {}
	_mutex.unlock()
	_building = false
	if result.has("stream"):
		_queue.append(result)
		if enabled and not _player.playing:
			_advance()


static func _lead_name(lead: StringName) -> String:
	match lead:
		&"ney":
			return "ней"
		&"qanun":
			return "канун"
		_:
			return "уд"


## Помехи: розовый шум с редкими щелчками. Белый для эфира слишком острый,
## а чистый розовый — слишком ровный, живой эфир потрескивает.
func _make_static() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var frames := Synth.RATE * 3
	var noise := Synth.pink_series(frames, rng)
	noise = Synth.band_pass(noise, 1900.0, 0.7)
	for i: int in frames:
		if rng.randf() > 0.9988:
			noise[i] += rng.randf_range(-0.6, 0.6)
	# Медленное дыхание уровня — эфир не стоит на месте.
	for i: int in frames:
		var t := float(i) / float(Synth.RATE)
		noise[i] = noise[i] * (0.7 + 0.3 * sin(t * TAU * 0.21))
	noise = Synth.normalise(noise, 0.6)
	# Стык петли не должен щёлкать: сводим начало с концом.
	var blend := Synth.RATE / 8
	for i: int in blend:
		var k := float(i) / float(blend)
		noise[i] = lerpf(noise[frames - blend + i], noise[i], k)
	return Synth.to_stream(noise, true)
