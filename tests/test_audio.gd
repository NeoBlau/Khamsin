extends TestCase
## Звук: синтез, лады, голос, радио.
##
## Слушать тестами нельзя, поэтому проверяется то, что можно измерить:
## дорожка не молчит и не клиппит, петля не щёлкает на стыке, интонация
## вопроса идёт вверх, а приём падает с расстоянием. Каждая из этих проверок
## соответствует конкретной слышимой поломке.


func _peak(buffer: PackedFloat32Array) -> float:
	var peak := 0.0
	for v: float in buffer:
		peak = maxf(peak, absf(v))
	return peak


func _rms(buffer: PackedFloat32Array) -> float:
	if buffer.is_empty():
		return 0.0
	var energy := 0.0
	for v: float in buffer:
		energy += v * v
	return sqrt(energy / float(buffer.size()))


func _finite(buffer: PackedFloat32Array) -> bool:
	for v: float in buffer:
		if is_nan(v) or is_inf(v):
			return false
	return true


# --- Синтез -----------------------------------------------------------------


func test_adsr_stays_in_range_and_starts_from_zero() -> void:
	check_near(Synth.adsr(0.0, 1.0, 0.1, 0.1, 0.7, 0.2), 0.0, 0.001, "атака начинается с нуля")
	check_near(Synth.adsr(0.1, 1.0, 0.1, 0.1, 0.7, 0.2), 1.0, 0.01, "пик в конце атаки")
	check_near(Synth.adsr(0.5, 1.0, 0.1, 0.1, 0.7, 0.2), 0.7, 0.01, "полка держит sustain")
	check_near(Synth.adsr(1.0, 1.0, 0.1, 0.1, 0.7, 0.2), 0.0, 0.001, "затухание уходит в ноль")
	for i: int in 40:
		var t := float(i) / 39.0
		var value := Synth.adsr(t, 1.0, 0.1, 0.15, 0.6, 0.25)
		check(value >= -0.001 and value <= 1.001, "огибающая в пределах на t=%.2f: %.3f" % [t, value])


func test_normalise_hits_the_requested_peak() -> void:
	var buffer := PackedFloat32Array([0.1, -0.2, 0.05])
	Synth.normalise(buffer, 0.8)
	check_near(_peak(buffer), 0.8, 0.001, "пик приведён к заданному")
	var silence := PackedFloat32Array([0.0, 0.0])
	Synth.normalise(silence, 0.8)
	check_near(_peak(silence), 0.0, 0.001, "тишина остаётся тишиной, а не делится на ноль")


func test_stream_round_trip_keeps_length_and_format() -> void:
	var buffer := PackedFloat32Array()
	buffer.resize(Synth.RATE)
	for i: int in buffer.size():
		buffer[i] = sin(float(i) * 0.01)
	var stream := Synth.to_stream(buffer, true)
	check_equal(stream.format, AudioStreamWAV.FORMAT_16_BITS, "16 бит")
	check_equal(stream.mix_rate, Synth.RATE, "частота дискретизации")
	check_equal(stream.data.size(), buffer.size() * 2, "два байта на кадр")
	check_equal(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "петля включена")
	check_equal(stream.loop_end, buffer.size(), "петля до конца")
	check_near(Synth.stream_seconds(stream), 1.0, 0.001, "длина в секундах")


func test_clipping_is_clamped_not_wrapped() -> void:
	# Переполнение при записи в 16 бит заворачивается: +1.2 стало бы громким
	# щелчком с обратным знаком. Это самый неприятный вид искажения.
	var stream := Synth.to_stream(PackedFloat32Array([1.6, -1.6]), false)
	check_equal(stream.data.decode_s16(0), 32767, "положительный пик прижат")
	check_equal(stream.data.decode_s16(2), -32767, "отрицательный пик прижат")


func test_filters_do_not_produce_garbage() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var noise := Synth.pink_series(Synth.RATE / 4, rng)
	check(_finite(noise), "розовый шум конечен")
	check(_peak(noise) <= 1.0, "розовый шум не выходит за единицу")
	check(_rms(noise) > 0.01, "розовый шум не тишина")
	for filtered: PackedFloat32Array in [
		Synth.low_pass(noise, 800.0),
		Synth.high_pass(noise, 800.0),
		Synth.band_pass(noise, 1200.0, 1.4),
		Synth.delay(noise, 0.05, 0.4, 0.5),
	]:
		check(_finite(filtered), "фильтр не даёт NaN")
		check_equal(filtered.size(), noise.size(), "длина сохраняется")


func test_low_pass_actually_removes_treble() -> void:
	# Сравниваем энергию высокого тона до и после. Если фильтр не работает,
	# числа совпадут, и это видно сразу.
	var frames := Synth.RATE / 2
	var high := PackedFloat32Array()
	high.resize(frames)
	for i: int in frames:
		high[i] = sin(float(i) / float(Synth.RATE) * TAU * 6000.0)
	var filtered := Synth.low_pass(high, 300.0)
	check(_rms(filtered) < _rms(high) * 0.2,
		"высокий тон задавлен: было %.3f, стало %.3f" % [_rms(high), _rms(filtered)])


func test_pluck_decays_and_holds_pitch() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var string := Synth.pluck(220.0, 1.0, 0.02, rng)
	check_equal(string.size(), Synth.RATE, "длина как заказана")
	check(_finite(string), "струна конечна")
	var head := string.slice(0, Synth.RATE / 10)
	var tail := string.slice(Synth.RATE * 8 / 10, Synth.RATE)
	check(_rms(tail) < _rms(head), "струна затухает: %.4f против %.4f" % [_rms(tail), _rms(head)])
	check(_rms(tail) > 0.0001, "но не умирает мгновенно")


func test_note_hz_matches_the_tuning() -> void:
	check_near(Synth.note_hz(0.0), 440.0, 0.01, "ля первой октавы")
	check_near(Synth.note_hz(12.0), 880.0, 0.01, "октава вверх")
	check_near(Synth.note_hz(-12.0), 220.0, 0.01, "октава вниз")
	# Четвертитон между ступенями — на нём и держится весь восточный колорит.
	check(Synth.note_hz(3.5) > Synth.note_hz(3.0), "полступени выше целой")
	check(Synth.note_hz(3.5) < Synth.note_hz(4.0), "и ниже следующей")


# --- Лады -------------------------------------------------------------------


func test_every_maqam_spans_an_octave() -> void:
	for id: StringName in Maqam.scale_ids():
		var steps: Array = Maqam.scale(id)
		check(steps.size() >= 8, "%s: не меньше восьми ступеней" % id)
		check_near(float(steps[0]), 0.0, 0.001, "%s: начинается с тоники" % id)
		check_near(float(steps[steps.size() - 1]), 12.0, 0.001, "%s: заканчивается октавой" % id)
		for i: int in steps.size() - 1:
			check(float(steps[i + 1]) > float(steps[i]), "%s: ступени возрастают" % id)


func test_quarter_tones_are_present_where_they_should_be() -> void:
	# Без четвертитонов раст — обычный мажор, а баяти — фригийский лад.
	# Эта проверка ловит «упрощение» ладов при правке данных.
	for id: StringName in [&"rast", &"bayati", &"saba", &"sikah"]:
		var fractional := 0
		for step: float in Maqam.scale(id):
			if not is_equal_approx(step, round(step)):
				fractional += 1
		check(fractional > 0, "%s: есть хотя бы одна дробная ступень" % id)


func test_degree_climbs_through_octaves() -> void:
	var tonic := Maqam.degree(&"nahawand", 0)
	var octave := Maqam.degree(&"nahawand", 7)
	check_near(octave - tonic, 12.0, 0.001, "седьмой шаг — это октава")
	check_near(Maqam.degree(&"nahawand", 14) - tonic, 24.0, 0.001, "две октавы")
	check(Maqam.degree(&"nahawand", -1) < tonic, "вниз тоже можно")


func test_rhythms_are_eight_eighths() -> void:
	for id: StringName in Maqam.rhythm_ids():
		var pattern := Maqam.rhythm(id)
		check_equal(pattern.length(), 8, "%s: восемь восьмых" % id)
		var strokes := 0
		for i: int in pattern.length():
			var symbol := pattern[i]
			check(symbol in ["D", "T", "k", "."], "%s: символ %s известен" % [id, symbol])
			if symbol != ".":
				strokes += 1
		# Вахда — это намеренно один дум и один так на такт: медленный цикл,
		# под который играют таксим. Порог в два удара, а не в три.
		check(strokes >= 2, "%s: ритм, а не тишина" % id)
		check(pattern[0] == "D", "%s: цикл начинается с дума" % id)


# --- Музыка -----------------------------------------------------------------


func test_music_renders_audible_and_bounded() -> void:
	var options := Music.Options.new()
	options.scale = &"hijaz"
	options.rhythm = &"maqsum"
	options.lead = &"oud"
	options.tempo = 96.0
	options.bars = 2
	var buffer := Music.render(1234, options)
	check(_finite(buffer), "музыка конечна")
	check(_peak(buffer) <= 1.0, "без клиппинга, пик %.3f" % _peak(buffer))
	check(_rms(buffer) > 0.02, "не тишина, rms %.3f" % _rms(buffer))
	var expected := Music.track_seconds(options)
	var actual := float(buffer.size()) / float(Synth.RATE)
	check(actual >= expected, "дорожка не короче фразы: %.2f против %.2f" % [actual, expected])
	check(actual < expected + 1.5, "и не длиннее её с хвостом")


func test_music_starts_and_ends_quietly() -> void:
	# Резкий старт буфера — это щелчок на каждом переходе между треками.
	var options := Music.Options.new()
	options.bars = 2
	var buffer := Music.render(77, options)
	check(absf(buffer[0]) < 0.05, "начало сведено в ноль: %.4f" % buffer[0])
	check(absf(buffer[buffer.size() - 1]) < 0.05, "и конец тоже")


func test_different_seeds_make_different_music() -> void:
	var options := Music.Options.new()
	options.bars = 2
	var a := Music.render(1, options)
	var b := Music.render(2, options)
	var same := 0
	var count := mini(a.size(), b.size())
	for i: int in count:
		if is_equal_approx(a[i], b[i]):
			same += 1
	check(same < count / 2, "две фразы отличаются")


func test_same_seed_makes_the_same_music() -> void:
	var options := Music.Options.new()
	options.bars = 2
	var a := Music.render(42, options)
	var b := Music.render(42, options)
	check_equal(a.size(), b.size(), "длина совпадает")
	var differ := 0
	for i: int in mini(a.size(), b.size()):
		if not is_equal_approx(a[i], b[i]):
			differ += 1
	check_equal(differ, 0, "один сид — одна и та же фраза")


func test_percussion_can_be_switched_off() -> void:
	var options := Music.Options.new()
	options.bars = 2
	options.percussion = false
	options.drone = false
	var bare := Music.render(5, options)
	options.percussion = true
	options.drone = true
	var full := Music.render(5, options)
	check(_rms(full) > 0.0, "полный состав звучит")
	check(_rms(bare) > 0.0, "одна мелодия тоже звучит")


# --- Голос ------------------------------------------------------------------


func test_line_plan_follows_the_text() -> void:
	var profile := Voice.profile(&"nadia")
	check(Voice.plan_line("", profile).is_empty(), "пустая строка не звучит")
	var short_plan := Voice.plan_line("Да", profile)
	var long_plan := Voice.plan_line("Машина старая, но она тебя довезёт", profile)
	check(long_plan.size() > short_plan.size(), "длинная фраза — больше слогов")
	for entry: Dictionary in long_plan:
		check(float(entry["pitch"]) > 40.0, "высота звука осмысленная")
		check(float(entry["length"]) > 0.0, "слог не нулевой длины")


func test_question_rises_and_statement_falls() -> void:
	var profile := Voice.profile(&"yusuf")
	var question := Voice.plan_line("Ты уже был на Точке семь?", profile)
	var statement := Voice.plan_line("Ты уже был на Точке семь.", profile)
	var q_first := float(question[0]["pitch"])
	var q_last := float(question[question.size() - 1]["pitch"])
	var s_first := float(statement[0]["pitch"])
	var s_last := float(statement[statement.size() - 1]["pitch"])
	check(q_last > q_first, "вопрос ведёт тон вверх: %.0f → %.0f" % [q_first, q_last])
	check(s_last < s_first, "утверждение оседает: %.0f → %.0f" % [s_first, s_last])


func test_commas_make_pauses() -> void:
	var profile := Voice.profile(&"nadia")
	var flowing := Voice.plan_line("Бери что унесёшь только не стекло", profile)
	var broken := Voice.plan_line("Бери, что, унесёшь, только, не, стекло", profile)
	var flowing_end := float(flowing[flowing.size() - 1]["at"])
	var broken_end := float(broken[broken.size() - 1]["at"])
	check(broken_end > flowing_end, "запятые удлиняют реплику: %.2f против %.2f" % [broken_end, flowing_end])


func test_voices_differ_between_characters() -> void:
	var nadia := Voice.profile(&"nadia")
	var yusuf := Voice.profile(&"yusuf")
	check(nadia.pitch > yusuf.pitch * 1.3, "у Надии голос заметно выше")
	check(yusuf.roughness > nadia.roughness, "у Юсуфа хрипота сильнее")
	var official := Voice.profile(&"official")
	check(official.pitch_range < nadia.pitch_range, "человек из правительства говорит ровно")


func test_derived_voice_is_stable_and_varied() -> void:
	var a := Voice.derived("Инженер на Точке 7")
	var b := Voice.derived("Инженер на Точке 7")
	check_near(a.pitch, b.pitch, 0.0001, "одно имя — один голос")
	check_near(a.speed, b.speed, 0.0001, "и один темп")
	var other := Voice.derived("Начальник смены, Хуфра")
	check(absf(other.pitch - a.pitch) > 1.0, "разные имена звучат по-разному")
	for name: String in ["Надия", "Юсуф", "Человек у колодца", "Дядя Валя"]:
		var profile := Voice.derived(name)
		check(profile.pitch > 60.0 and profile.pitch < 320.0, "%s: высота в человеческом диапазоне" % name)
		check(profile.speed > 0.4 and profile.speed < 2.0, "%s: темп разумный" % name)


func test_rendered_line_is_audible() -> void:
	var buffer := Voice.render_line("Проверка связи.", Voice.profile(&"radio_host"), 3)
	check(_finite(buffer), "голос конечен")
	check(_rms(buffer) > 0.02, "голос слышно, rms %.3f" % _rms(buffer))
	check(_peak(buffer) <= 1.0, "без клиппинга")


# --- Радио ------------------------------------------------------------------


func _radio() -> Radio:
	var radio := Radio.new()
	radio.load_stations()
	return radio


func test_stations_load_from_data() -> void:
	var radio := _radio()
	check(radio.stations.size() >= 5, "станций загружено: %d" % radio.stations.size())
	var seen: Array[StringName] = []
	for station: RadioStation in radio.stations:
		check(not seen.has(station.id), "идентификатор %s не повторяется" % station.id)
		seen.append(station.id)
		check(station.frequency > 0.0, "%s: частота задана" % station.id)
		check(not station.scales.is_empty(), "%s: есть лады" % station.id)
		check(not station.rhythms.is_empty(), "%s: есть ритмы" % station.id)
		check(station.tempo_range.x <= station.tempo_range.y, "%s: темп не вывернут" % station.id)
		for scale: StringName in station.scales:
			check(Maqam.SCALES.has(scale), "%s: лад %s существует" % [station.id, scale])
		for rhythm: StringName in station.rhythms:
			check(Maqam.RHYTHMS.has(rhythm), "%s: ритм %s существует" % [station.id, rhythm])


func test_every_station_has_something_to_say() -> void:
	var radio := _radio()
	for station: RadioStation in radio.stations:
		check(not station.station_id_lines.is_empty(), "%s: представляется в эфире" % station.id)
		if station.talk_chance > 0.0:
			check(not station.talk_lines.is_empty(), "%s: ведущему есть что сказать" % station.id)
		if station.advert_chance > 0.0:
			check(not station.advert_lines.is_empty(), "%s: реклама не пустая" % station.id)


func test_reception_falls_with_distance() -> void:
	var station := RadioStation.new()
	station.transmitter = Vector2.ZERO
	station.range_km = 20.0
	check_near(station.reception(Vector2.ZERO), 1.0, 0.001, "у передатчика чисто")
	check_near(station.reception(Vector2(10000.0, 0.0)), 1.0, 0.001, "в ближней зоне чисто")
	var far := station.reception(Vector2(18000.0, 0.0))
	check(far < 1.0 and far > 0.0, "на краю зоны помехи, но не тишина: %.2f" % far)
	check(station.reception(Vector2(60000.0, 0.0)) < far, "дальше — хуже")
	var global_station := RadioStation.new()
	check_near(global_station.reception(Vector2(500000.0, 0.0)), 1.0, 0.001,
		"станция без радиуса слышна везде")


func test_night_station_wraps_around_midnight() -> void:
	var station := RadioStation.new()
	station.hours = Vector2(23.0, 4.0)
	check(station.on_air_at(23.5), "в 23:30 в эфире")
	check(station.on_air_at(1.0), "в час ночи в эфире")
	check(not station.on_air_at(12.0), "днём молчит")
	check(not station.on_air_at(22.0), "до полуночи ещё не вышла")
	var always := RadioStation.new()
	check(always.on_air_at(0.0) and always.on_air_at(15.0), "круглосуточная всегда в эфире")


func test_pirate_station_is_hard_to_find() -> void:
	var radio := _radio()
	var pirate: RadioStation = null
	for station: RadioStation in radio.stations:
		if station.id == &"pirate":
			pirate = station
	if not check(pirate != null, "пиратская волна есть в данных"):
		return
	check(pirate.range_km < 50.0, "передатчик слабый: %.0f км" % pirate.range_km)
	check(not pirate.on_air_at(12.0), "днём её нет")
	check(pirate.on_air_at(0.5), "ночью есть")
	check_near(pirate.reception(pirate.transmitter), 1.0, 0.001, "у сарая слышно чисто")
	check(pirate.reception(Vector2.ZERO) < 0.2, "из центра карты почти не поймать: %.2f"
		% pirate.reception(Vector2.ZERO))
	check(pirate.reception(pirate.transmitter + Vector2(3000.0, 0.0)) > 0.9,
		"в трёх километрах от передатчика ещё чисто")


# --- Эфир вживую ------------------------------------------------------------


## Юнит-тесты выше проверяют куски. Этот — что радио действительно выходит в
## эфир: план сегмента уходит в рабочий поток, возвращается потоком, встаёт в
## очередь и начинает играть. Каждое из этих звеньев легко сломать так, что
## отдельные функции останутся исправными, а звука не будет.
func test_radio_actually_goes_on_air() -> void:
	Audio.radio.listen_from(Vector2.ZERO, 12.0)
	Audio.radio.set_enabled(true)
	var label := ""
	for _i: int in 900:
		await tree().process_frame
		label = Audio.radio.now_playing()
		if not label.is_empty() and not label.ends_with("помехи"):
			break
	check(not label.is_empty(), "в эфире что-то есть: «%s»" % label)
	check(label.contains(Audio.radio.current().name) or label.contains("помехи"),
		"строка эфира называет станцию: «%s»" % label)
	Audio.radio.set_enabled(false)
	check_equal(Audio.radio.now_playing(), "", "выключенное радио молчит")


func test_tuning_moves_between_stations_on_air() -> void:
	Audio.radio.listen_from(Vector2.ZERO, 12.0)
	var pool := Audio.radio.available()
	if not check(pool.size() >= 2, "днём доступно больше одной станции: %d" % pool.size()):
		return
	var first := Audio.radio.current()
	Audio.radio.step_station(1)
	var second := Audio.radio.current()
	check(first != second, "крутилка переключила станцию")
	Audio.radio.step_station(-1)
	check_equal(Audio.radio.current(), first, "и вернулась обратно")


## Ночная станция не должна попадать в перебор днём — иначе крутилка
## останавливается на тишине, и это выглядит как зависшее радио.
func test_daytime_tuning_skips_night_stations() -> void:
	Audio.radio.listen_from(Vector2.ZERO, 13.0)
	for station: RadioStation in Audio.radio.available():
		check(station.on_air_at(13.0), "%s: днём в эфире" % station.id)
	Audio.radio.listen_from(Vector2.ZERO, 1.0)
	var night := Audio.radio.available()
	var ids: Array[StringName] = []
	for station: RadioStation in night:
		ids.append(station.id)
	check(ids.has(&"oasis"), "ночью Волна Оазиса доступна")
