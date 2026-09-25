class_name SandField
extends RefCounted
## Песок, который помнит, что по нему проехали.
##
## Зачем отдельный слой. Рельеф в игре — чистая функция от координат: высота
## считается шумом и одинакова всегда. Это хорошо для стриминга (любой кусок
## карты восстанавливается из зерна) и плохо для песка: по рыхлому песку
## нельзя проехать и не оставить следа, а функция следа не помнит.
##
## Поэтому поверх рельефа лежит разреженная сетка поправок. Ячейка хранит
## четыре числа: насколько продавлено, сколько материала выдавило в бруствер,
## насколько песок взрыхлён и когда его трогали последний раз. Рельеф остаётся
## функцией, а память живёт отдельно — и только там, где по ней ездили.
##
## Что это даёт в физике, а не на картинке:
##   * колея реальна для подвески. Контактная точка опускается на поправку, и
##     машина проваливается в собственный след;
##   * взрыхлённый песок глубже проседает под колесом. Второй проход по своей
##     же колее хуже первого — так оно и есть в дюнах;
##   * взрыхлённый песок хуже держит. Буксуя на месте, колесо роет себе яму и
##     теряет сцепление, вместо того чтобы вечно грести с постоянной тягой;
##   * бруствер по краям колеи выталкивает колесо наружу, и из глубокой колеи
##     надо выезжать, а не выруливать.
##
## Чего это не даёт, и врать тут незачем: это не симуляция отдельных песчинок.
## Каждая песчинка в кадре не живёт и жить не будет — ни здесь, ни в играх, на
## которые принято ссылаться. Здесь симулируется то, что игрок чувствует
## рулём: продавливание, осыпание по углу естественного откоса и рыхлость.

## Сторона ячейки, метры. Полметра — компромисс: колесо шириной 0.3 м должно
## попадать в одну-две ячейки, иначе колея размазывается в широкую канаву.
const CELL := 0.5
## Ячеек в плитке по стороне. Плитка — единица жизни и смерти: словарь из
## сотен тысяч отдельных ячеек Godot переживёт, но обход их каждый кадр — нет.
const TILE := 32
const TILE_SPAN := float(TILE) * CELL

## Угол естественного откоса сухого песка, градусы. Всё, что круче, осыпается.
const REPOSE_DEGREES := 34.0
## Скорость осыпания: доля превышения, уходящая соседу за секунду.
const SLUMP_RATE := 2.6
## Ветер засыпает колею сам по себе, метры в секунду глубины. Медленно:
## след должен жить минуты, а не секунды.
const WIND_FILL := 0.0045
## Рыхлость слёживается быстрее, чем зарастает колея: песок оседает раньше,
## чем яма исчезает.
const SETTLE_RATE := 0.06
## Глубже машина не роет: дальше она сидит на мостах, а не на колёсах.
const MAX_DEPTH := 0.34
## Какая доля просадки колеса остаётся в песке насовсем.
##
## Колесо проседает на sinkage — но это просадка под нагрузкой, и часть её
## упругая: песок под пятном спрессовался и после проезда частично поднялся
## обратно. В грунте остаётся только пластическая доля.
##
## Число важнее, чем кажется. Если записывать в колею всю просадку, получается
## петля с усилением: колея глубже -> опора ниже -> колесо проседает сильнее ->
## колея ещё глубже. Машина уходит в песок по мосты за несколько секунд стоя
## на ровном месте. С долей меньше единицы петля сходится.
const PLASTIC_FRACTION := 0.42
## Дальше этого радиуса от игрока плитки выгружаются. Пустыня забывает следы,
## и это не уступка производительности, а то, как оно и есть.
const KEEP_RADIUS := 260.0

## Ключ плитки (Vector2i) -> PackedFloat32Array из TILE*TILE*3:
## [глубина, бруствер, рыхлость] на ячейку. Один плоский массив вместо трёх —
## меньше обращений по ссылке в горячем цикле осыпания.
var _tiles: Dictionary = {}
## Плитки, которых касались с последнего пересчёта. Осыпать всю карту незачем.
var _active: Dictionary = {}
var _slump_cursor: int = 0

## Сколько ячеек пересчитывается за один шаг. Ограничение по времени, а не по
## охвату: на слабой машине песок оседает медленнее, но кадр не проседает.
var budget: int = 4096
## Выключатель для стендов и замеров: с ним поле перестаёт что-либо помнить, и
## машина едет по идеально гладкому рельефу. В игре всегда включено.
var enabled: bool = true


static func repose_slope() -> float:
	return tan(deg_to_rad(REPOSE_DEGREES))


func tile_count() -> int:
	return _tiles.size()


func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))


func tile_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / TILE), floori(float(cell.y) / TILE))


func _tile_data(key: Vector2i, create: bool) -> PackedFloat32Array:
	var found: Variant = _tiles.get(key)
	if found != null:
		return found as PackedFloat32Array
	if not create:
		return PackedFloat32Array()
	var fresh := PackedFloat32Array()
	fresh.resize(TILE * TILE * 3)
	fresh.fill(0.0)
	_tiles[key] = fresh
	return fresh


func _index_in_tile(cell: Vector2i, key: Vector2i) -> int:
	var lx := cell.x - key.x * TILE
	var ly := cell.y - key.y * TILE
	return (ly * TILE + lx) * 3


## Продавить колею. `depth` — насколько глубоко ушло колесо, `width` — ширина
## пятна, `looseness` — насколько колесо взрыхлило песок (буксующее рыхлит
## сильнее катящегося).
##
## Материал не исчезает: сколько продавили, столько и выдавило по краям. Это не
## педантизм, а то, из-за чего из глубокой колеи трудно выехать вбок.
## `plough` — насколько колесо сейчас перемещает грунт, 0..1.
##
## Множитель общий и для лунки, и для бруствера, и это не упрощение. Колею
## роет только работающее колесо: катящееся по новому месту или срезающее
## грунт буксованием. Стоящее лишь уминает песок под собой — но его просадка
## уже посчитана в модели шины и уже учтена в радиусе качения, так что писать
## её ещё и в грунт значит считать одно и то же дважды. Последствия у этой
## ошибки не косметические: машина, простоявшая минуту на рыхлом песке,
## оказывается в лунке по ступицы и не трогается с места вовсе.
func carve(
	position: Vector3,
	width: float,
	depth: float,
	looseness: float,
	softness: float,
	plough: float = 1.0,
	along: Vector2 = Vector2.ZERO
) -> void:
	if not enabled or depth <= 0.0 or softness <= 0.0 or plough <= 0.01:
		return
	var effective := minf(depth * softness * PLASTIC_FRACTION, MAX_DEPTH)
	# Зона продавливания шире пятна контакта, и это не поправка на сетку, а
	# механика грунта: песок срезается по поверхности сдвига, которая выходит
	# за колесо. Нижняя граница по размеру ячейки нужна отдельно — узкая шина
	# иначе попадает в одну ячейку, а билинейная выборка размазывает её на
	# четыре, и колея получается вчетверо мельче, чем колесо её продавило.
	var edge := maxf(width * 0.5, CELL)
	var reach := edge + CELL * 1.5
	var here := Vector2(position.x, position.z)
	var low := cell_of(position.x - reach, position.z - reach)
	var high := cell_of(position.x + reach, position.z + reach)
	for cy: int in range(low.y, high.y + 1):
		for cx: int in range(low.x, high.x + 1):
			# Расстояние меряется до центра ячейки, а не в шагах сетки: шагами
			# выходит, что по диагонали ближе, чем по прямой.
			var centre := Vector2((float(cx) + 0.5) * CELL, (float(cy) + 0.5) * CELL)
			var distance := centre.distance_to(here)
			if distance <= edge:
				# Внутри пятна — давим. К краю мельче: колесо круглое.
				var falloff := 1.0 - (distance / maxf(edge, 0.01)) * 0.55
				_press(Vector2i(cx, cy), effective * falloff * plough, looseness)
			elif distance <= reach:
				# Сразу за пятном — бруствер из того, что выдавило. Но только
				# вбок и назад: колесо гонит песок в стороны и себе под зад, а
				# не насыпает вал на дороге перед собой. Валик впереди —
				# ошибка с последствиями: машина едет по собственному
				# бруствepу, теряет ход и закапывается на ровном месте.
				if along != Vector2.ZERO and (centre - here).normalized().dot(along) > 0.35:
					continue
				_heap(Vector2i(cx, cy), effective * 0.34 * plough, looseness * 0.6)


func _press(cell: Vector2i, depth: float, looseness: float) -> void:
	var key := tile_of(cell)
	var data := _tile_data(key, true)
	var i := _index_in_tile(cell, key)
	data[i] = minf(maxf(data[i], depth), MAX_DEPTH)
	data[i + 2] = clampf(maxf(data[i + 2], looseness), 0.0, 1.0)
	_tiles[key] = data
	_active[key] = true


## Насыпать бруствер.
##
## Высота берётся максимумом, а не суммой, и это следует из сохранения
## материала: в валик ушло ровно то, что вынули из колеи, и больше взяться
## неоткуда, сколько бы раз колесо ни прошло по одному месту. Сумма же растёт
## с частотой опроса — сто двадцать касаний в секунду упирают валик в потолок
## за долю секунды, и машина встаёт перед собственной насыпью в четырнадцать
## сантиметров.
func _heap(cell: Vector2i, height: float, looseness: float) -> void:
	var key := tile_of(cell)
	var data := _tile_data(key, true)
	var i := _index_in_tile(cell, key)
	data[i + 1] = minf(maxf(data[i + 1], height), MAX_DEPTH * 0.35)
	data[i + 2] = clampf(maxf(data[i + 2], looseness), 0.0, 1.0)
	_tiles[key] = data
	_active[key] = true


## Поправка к высоте рельефа в точке, метры. Отрицательная в колее,
## положительная на бруствере. Билинейная: по ступенькам ездить нельзя.
func offset(x: float, z: float) -> float:
	return _sample(x, z, 0) * -1.0 + _sample(x, z, 1)


## Рыхлость в точке, 0..1.
func looseness(x: float, z: float) -> float:
	return clampf(_sample(x, z, 2), 0.0, 1.0)


func _sample(x: float, z: float, channel: int) -> float:
	var fx := x / CELL - 0.5
	var fz := z / CELL - 0.5
	var x0 := floori(fx)
	var z0 := floori(fz)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var a := _raw(Vector2i(x0, z0), channel)
	var b := _raw(Vector2i(x0 + 1, z0), channel)
	var c := _raw(Vector2i(x0, z0 + 1), channel)
	var d := _raw(Vector2i(x0 + 1, z0 + 1), channel)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func _raw(cell: Vector2i, channel: int) -> float:
	var key := tile_of(cell)
	var found: Variant = _tiles.get(key)
	if found == null:
		return 0.0
	return (found as PackedFloat32Array)[_index_in_tile(cell, key) + channel]


## Шаг релаксации. Три процесса сразу, и все три — физика, а не косметика:
## осыпание по углу естественного откоса, засыпание ветром и слёживание.
func relax(dt: float, centre: Vector3) -> void:
	_forget_far(centre)
	if _active.is_empty():
		return
	var keys := _active.keys()
	var per_tile := TILE * TILE
	var tiles_per_step := maxi(1, budget / per_tile)
	# Если плиток больше, чем успеваем за шаг, каждая достаётся реже — и её
	# шаг времени растягивается ровно во столько же раз. Иначе песок оседает
	# тем медленнее, чем больше наездили, и это было бы видно.
	var stretch := maxf(1.0, float(keys.size()) / float(tiles_per_step))
	for _step: int in tiles_per_step:
		if keys.is_empty():
			return
		_slump_cursor = (_slump_cursor + 1) % keys.size()
		var key: Vector2i = keys[_slump_cursor]
		if not _relax_tile(key, dt * stretch):
			_active.erase(key)
			keys = _active.keys()
			if keys.is_empty():
				return


## Возвращает false, если плитка успокоилась и её можно не трогать.
func _relax_tile(key: Vector2i, dt: float) -> bool:
	var data := _tile_data(key, false)
	if data.is_empty():
		return false
	var limit := repose_slope() * CELL
	var alive := false
	var fill := WIND_FILL * dt
	for ly: int in TILE:
		for lx: int in TILE:
			var i := (ly * TILE + lx) * 3
			var depth := data[i]
			var ridge := data[i + 1]
			var loose := data[i + 2]
			if depth <= 0.0005 and ridge <= 0.0005 and loose <= 0.001:
				continue
			alive = true
			# Бруствер сыплется в яму рядом: материал возвращается туда,
			# откуда его выдавили, и колея зарастает изнутри, а не сверху.
			if ridge > 0.0 and depth > 0.0:
				var returned := minf(ridge, depth) * SLUMP_RATE * dt
				ridge -= returned
				depth -= returned
			# Осыпание по откосу: если перепад с соседом круче предельного,
			# лишнее съезжает вниз.
			for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := lx + side.x
				var ny := ly + side.y
				if nx < 0 or ny < 0 or nx >= TILE or ny >= TILE:
					continue
				var j := (ny * TILE + nx) * 3
				var difference := depth - data[j]
				if difference > limit:
					var flow := (difference - limit) * 0.25 * SLUMP_RATE * dt
					depth -= flow
					data[j] = data[j] + flow
			depth = maxf(depth - fill, 0.0)
			ridge = maxf(ridge - fill * 1.6, 0.0)
			loose = maxf(loose - SETTLE_RATE * dt, 0.0)
			data[i] = depth
			data[i + 1] = ridge
			data[i + 2] = loose
	_tiles[key] = data
	if not alive:
		_tiles.erase(key)
	return alive


func _forget_far(centre: Vector3) -> void:
	if _tiles.size() < 64:
		return
	var limit := KEEP_RADIUS + TILE_SPAN
	for key: Vector2i in _tiles.keys():
		var tile_centre := Vector2(
			(float(key.x) + 0.5) * TILE_SPAN, (float(key.y) + 0.5) * TILE_SPAN
		)
		if tile_centre.distance_to(Vector2(centre.x, centre.z)) > limit:
			_tiles.erase(key)
			_active.erase(key)


func clear() -> void:
	_tiles.clear()
	_active.clear()
	_slump_cursor = 0
