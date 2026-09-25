extends TestCase
## Песок, который помнит колею. Проверяем не картинку, а то, из-за чего меняется
## поведение машины: глубину, материал, осыпание и стоимость всего этого.


func _sand() -> SandField:
	return SandField.new()


func test_a_wheel_leaves_a_dent() -> void:
	var sand := _sand()
	check_equal(sand.offset(0.0, 0.0), 0.0, "нетронутый песок ровный")
	sand.carve(Vector3.ZERO, 0.3, 0.12, 0.5, 1.0)
	check(sand.offset(0.0, 0.0) < -0.02, "под колесом появилась яма")
	check(sand.looseness(0.0, 0.0) > 0.0, "песок взрыхлён")


## Материал не исчезает: что продавили, то выдавило по краям. Из-за бруствера
## из глубокой колеи нельзя выехать вбок, можно только выехать.
func test_what_is_pressed_down_comes_up_at_the_sides() -> void:
	var sand := _sand()
	sand.carve(Vector3.ZERO, 0.3, 0.30, 0.5, 1.0)
	check(sand.offset(0.0, 0.0) < 0.0, "внутри колеи ниже уровня")
	# Где именно окажется гребень бруствера, зависит от ширины колеса и шага
	# сетки, поэтому ищем его сканированием, а не пробой в угаданной точке:
	# тест на механику не должен падать от того, что поменяли шину.
	var highest := 0.0
	var at := 0.0
	for i: int in 60:
		var x := float(i) * 0.05
		var here := sand.offset(x, 0.0)
		if here > highest:
			highest = here
			at = x
	check(highest > 0.0, "по краю колеи есть бруствер")
	check(at > 0.15, "и он снаружи колеи, а не в ней: %.2f м от оси" % at)


func test_the_dent_does_not_grow_without_bound() -> void:
	var sand := _sand()
	for _i: int in 200:
		sand.carve(Vector3.ZERO, 0.3, 0.9, 1.0, 1.0)
	check(
		absf(sand.offset(0.0, 0.0)) <= SandField.MAX_DEPTH + 0.01,
		"глубже предела колесо не роет: дальше машина сидит на мостах"
	)


## Твёрдый грунт следов не держит. Softness приходит из того же коэффициента
## просадки, что и физика колеса, так что камень тут не оговорка.
func test_hard_ground_keeps_no_tracks() -> void:
	var sand := _sand()
	sand.carve(Vector3.ZERO, 0.3, 0.2, 0.5, 0.0)
	check_equal(sand.offset(0.0, 0.0), 0.0, "по камню колеи нет")


func test_tracks_fade_with_time() -> void:
	var sand := _sand()
	sand.carve(Vector3.ZERO, 0.4, 0.25, 0.8, 1.0)
	var fresh := absf(sand.offset(0.0, 0.0))
	for _i: int in 240:
		sand.relax(0.25, Vector3.ZERO)
	var later := absf(sand.offset(0.0, 0.0))
	check(later < fresh, "колея заросла: было %.3f, стало %.3f" % [fresh, later])


## Осыпание идёт по углу естественного откоса, а не «по чуть-чуть». Стенка
## колеи круче тридцати четырёх градусов держаться не может.
func test_walls_steeper_than_the_angle_of_repose_collapse() -> void:
	var sand := _sand()
	sand.carve(Vector3.ZERO, 0.3, SandField.MAX_DEPTH, 1.0, 1.0)
	var wall := absf(sand.offset(0.0, 0.0) - sand.offset(SandField.CELL, 0.0))
	for _i: int in 400:
		sand.relax(0.1, Vector3.ZERO)
	var after := absf(sand.offset(0.0, 0.0) - sand.offset(SandField.CELL, 0.0))
	check(after <= wall, "стенка не стала круче")
	check(
		after <= SandField.repose_slope() * SandField.CELL + 0.02,
		"уклон улёгся в угол естественного откоса: %.3f м на ячейку" % after
	)


## Рыхлость слёживается раньше, чем зарастает яма: песок оседает, но яма
## остаётся. Так оно и выглядит на утро после ночной езды.
func test_looseness_settles_before_the_dent_fills() -> void:
	var sand := _sand()
	sand.carve(Vector3.ZERO, 0.4, 0.3, 1.0, 1.0)
	for _i: int in 60:
		sand.relax(0.2, Vector3.ZERO)
	check(sand.looseness(0.0, 0.0) < 0.5, "рыхлость осела")
	check(absf(sand.offset(0.0, 0.0)) > 0.02, "яма ещё на месте")


## Пустыня забывает: плитки вдали от игрока выгружаются, иначе за час езды
## словарь вырастает в гигабайты.
func test_the_desert_forgets_distant_tracks() -> void:
	var sand := _sand()
	for i: int in 400:
		sand.carve(Vector3(float(i) * 4.0, 0.0, 0.0), 0.3, 0.2, 0.5, 1.0)
	var everywhere := sand.tile_count()
	check(everywhere > 64, "следов накопилось: %d плиток" % everywhere)
	sand.relax(0.1, Vector3(1600.0, 0.0, 0.0))
	check(sand.tile_count() < everywhere, "дальние плитки выгружены")


## Стоимость шага релаксации ограничена бюджетом, а не размером карты. Если
## это сломается, песок начнёт съедать кадр тем сильнее, чем дольше играешь.
func test_relaxation_cost_does_not_grow_with_the_map() -> void:
	var small := _sand()
	for i: int in 20:
		small.carve(Vector3(float(i) * 2.0, 0.0, 0.0), 0.3, 0.2, 0.5, 1.0)
	var big := _sand()
	for i: int in 900:
		big.carve(Vector3(float(i % 30) * 2.0, 0.0, float(i / 30) * 2.0), 0.3, 0.2, 0.5, 1.0)

	var start := Time.get_ticks_usec()
	small.relax(0.016, Vector3.ZERO)
	var cheap := Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	big.relax(0.016, Vector3.ZERO)
	var costly := Time.get_ticks_usec() - start
	check(
		costly < maxi(cheap, 50) * 6,
		"большая карта не дороже маленькой в разы: %d мкс против %d" % [costly, cheap]
	)
	check(costly < 6000, "шаг релаксации укладывается в кадр: %d мкс" % costly)


func test_sampling_is_smooth_not_stepped() -> void:
	var sand := _sand()
	sand.carve(Vector3.ZERO, 0.6, 0.3, 0.5, 1.0)
	# Между соседними точками не должно быть ступенек: по ступенькам подвеска
	# стучит там, где в жизни гладко.
	var previous := sand.offset(-1.5, 0.0)
	var worst := 0.0
	for i: int in 60:
		var x := -1.5 + float(i) * 0.05
		var here := sand.offset(x, 0.0)
		worst = maxf(worst, absf(here - previous))
		previous = here
	check(worst < 0.06, "перепад между соседними пробами мал: %.4f м" % worst)


## Стоящая машина не должна окружать себя валиком. Бруствер — это грунт,
## сгребённый катящимся колесом; у стоящего его брать неоткуда.
##
## Проверка не теоретическая. Без множителя по скорости грузовик, постоявший
## минуту, трогался из собственной лунки с валиком по краю и терял на этом две
## секунды разгона — на твёрдом щебне, где песка нет вовсе.
func test_a_parked_wheel_leaves_nothing() -> void:
	var standing := _sand()
	standing.carve(Vector3.ZERO, 0.3, 0.2, 0.3, 1.0, 0.0)
	var rolling := _sand()
	rolling.carve(Vector3.ZERO, 0.3, 0.2, 0.3, 1.0, 1.0)

	var highest_rolling := 0.0
	for i: int in 60:
		check_equal(standing.offset(float(i) * 0.05, 0.0), 0.0, "стоящее колесо не роет")
		highest_rolling = maxf(highest_rolling, rolling.offset(float(i) * 0.05, 0.0))
	check(rolling.offset(0.0, 0.0) < 0.0, "катящееся оставляет колею")
	check(highest_rolling > 0.0, "и бруствер по краю")
	check_equal(standing.tile_count(), 0, "от стоянки в поле не остаётся ничего")


## Удар не штампует яму предельной глубины. Пластическая деформация идёт за
## длительной нагрузкой, а не за пиком, и фильтр просадки в колесе — именно об
## этом. Здесь проверяется следствие на стороне поля: один глубокий мазок
## оставляет столько же, сколько долгое стояние, а не в разы больше.
func test_depth_does_not_add_up_with_every_touch() -> void:
	var once := _sand()
	once.carve(Vector3.ZERO, 0.3, 0.5, 0.2, 1.0, 1.0)
	var many := _sand()
	for _i: int in 120:
		many.carve(Vector3.ZERO, 0.3, 0.5, 0.2, 1.0, 1.0)
	check_near(
		absf(once.offset(0.0, 0.0)),
		absf(many.offset(0.0, 0.0)),
		0.001,
		"глубина не копится от числа касаний"
	)


## Видимая лента следа. Проверяется не картинка, а то, что она вообще
## появляется, живёт столько же, сколько физическая колея, и не растёт без
## предела: лента строится каждый кадр, и утечка сегментов тут — это утечка
## вершин в каждом кадре до конца поездки.
func test_the_ribbon_follows_the_wheels() -> void:
	var tracks := SandTracks.new()
	host.add_child(tracks)
	var truck := VehicleBody.new()
	truck.config_id = &"tabuk_6t"
	truck.player_controlled = false
	truck.surface_provider = func(_p: Vector3) -> Surface: return Surface.get_by_id(&"sand_soft")
	host.add_child(truck)
	tracks.attach(truck)
	check_equal(tracks.segment_count(), 0, "пока не ехали — следа нет")

	# Ведём колёса вручную: поднимать полноценный стенд ради ленты незачем,
	# она читает только контакт, просадку и покрытие.
	var laid := 0
	for step: int in 200:
		for wheel: VehicleWheel in truck.wheels:
			wheel.grounded = true
			wheel.surface = Surface.get_by_id(&"sand_soft")
			wheel.sinkage = 0.09
			wheel.contact_point = Vector3(float(step) * 0.4, 0.0, wheel.spec.position.x)
		tracks._collect()
		laid = tracks.segment_count()
	check(laid > 0, "лента появилась")
	check(
		laid <= SandTracks.MEMORY * truck.wheels.size(),
		"и не растёт без предела: %d сегментов" % laid
	)

	# Стареет она с той же скоростью, с какой ветер засыпает настоящую колею.
	tracks._age(SandTracks.lifetime() + 1.0)
	check_equal(tracks.segment_count(), 0, "старый след исчезает целиком")
	tracks.queue_free()
	truck.queue_free()


## Видимый след и физический должны жить одинаково: борозда, которую видно
## там, где подвеска её уже не чувствует, хуже, чем отсутствие борозды.
func test_the_ribbon_lives_as_long_as_the_rut() -> void:
	var sand := _sand()
	sand.carve(Vector3.ZERO, 0.4, 0.3, 0.5, 1.0, 1.0)
	var life := SandTracks.lifetime()
	var elapsed := 0.0
	while elapsed < life * 3.0 and absf(sand.offset(0.0, 0.0)) > 0.002:
		sand.relax(0.25, Vector3.ZERO)
		elapsed += 0.25
	check_between(
		elapsed, life * 0.3, life * 2.5,
		"физическая колея живёт того же порядка, что и лента (%.0f с против %.0f с)"
			% [elapsed, life]
	)


## Колесо гонит песок в стороны и себе под зад, а не насыпает вал на дороге
## перед собой. Ошибка с последствиями: машина, едущая по собственному
## брустверу, теряет ход и закапывается на ровном месте — спущенные колёса при
## этом «переставали помогать», хотя дело было не в них.
func test_the_berm_never_lands_in_front_of_the_wheel() -> void:
	var sand := _sand()
	var forward := Vector2(1.0, 0.0)
	sand.carve(Vector3.ZERO, 0.4, 0.3, 0.4, 1.0, 1.0, forward)
	var ahead := sand.offset(0.95, 0.0)
	var beside := sand.offset(0.0, 0.95)
	check(ahead <= 0.0, "впереди колеса насыпи нет: %.3f м" % ahead)
	check(beside > 0.0, "сбоку есть: %.3f м" % beside)


## Высота бруствера ограничена тем, сколько материала вынули из колеи, а не
## тем, сколько раз опросили физику. Сумма вместо максимума упирала валик в
## потолок за долю секунды: сто двадцать касаний в секунду на каждое колесо.
func test_the_berm_is_bounded_by_the_rut_it_came_from() -> void:
	var once := _sand()
	once.carve(Vector3.ZERO, 0.4, 0.2, 0.4, 1.0, 1.0)
	var many := _sand()
	for _i: int in 240:
		many.carve(Vector3.ZERO, 0.4, 0.2, 0.4, 1.0, 1.0)

	var highest_once := 0.0
	var highest_many := 0.0
	for i: int in 40:
		var x := float(i) * 0.05
		highest_once = maxf(highest_once, once.offset(x, 0.0))
		highest_many = maxf(highest_many, many.offset(x, 0.0))
	check_near(highest_many, highest_once, 0.002, "валик не растёт от числа касаний")
	check(
		highest_once < absf(once.offset(0.0, 0.0)),
		"и он ниже самой колеи: %.3f против %.3f" % [highest_once, absf(once.offset(0.0, 0.0))]
	)
