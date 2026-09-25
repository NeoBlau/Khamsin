class_name Homes
extends RefCounted
## Дома героя и гаражи при них.
##
## Дом — это не украшение и не трофей. В нём бесплатно ночуют, в гараже
## оставляют машину, и именно гараж делает вторую машину осмысленной: пока её
## негде держать, покупать её незачем.
##
## Дома открываются по сюжету или покупаются. Ключ от бокса на заставе,
## например, выдают вместе с маршрутом, которого не существует, — и купить
## его нельзя ни за какие деньги.

class Home:
	extends RefCounted
	var id: StringName = &""
	var name: String = ""
	var settlement: StringName = &""
	## Смещение от центра посёлка, метры.
	var offset: Vector2 = Vector2.ZERO
	var garage_slots: int = 1
	## Флаг, без которого дом не откроется. Пусто — доступен сразу.
	var unlock_flag: StringName = &""
	## Ноль — не продаётся: такой дом только дают.
	var price: float = 0.0
	var description: String = ""
	var rooms: Array[Dictionary] = []

	func world_position() -> Vector3:
		var place := World.settlement(settlement)
		if place == null:
			return Vector3.ZERO
		return Vector3(place.position.x + offset.x, place.ground_height, place.position.y + offset.y)

	func is_owned() -> bool:
		return bool(GameState.flag(StringName("home_owned_%s" % id)))

	func is_available() -> bool:
		return unlock_flag == &"" or bool(GameState.flag(unlock_flag))


const DATA_PATH := "res://data/world/homes.json"

static var _homes: Array[Home] = []
static var _by_id: Dictionary[StringName, Home] = {}


static func ensure_loaded() -> void:
	if not _homes.is_empty():
		return
	var text := FileAccess.get_file_as_string(DATA_PATH)
	if text.is_empty():
		push_warning("Дома: %s не читается" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		push_warning("Дома: %s не разобран" % DATA_PATH)
		return
	for entry: Variant in parsed as Array:
		var home := _from_dict(entry as Dictionary)
		_homes.append(home)
		_by_id[home.id] = home


static func _from_dict(data: Dictionary) -> Home:
	var home := Home.new()
	home.id = StringName(data.get("id", ""))
	home.name = String(data.get("name", ""))
	home.settlement = StringName(data.get("settlement", ""))
	var offset: Array = data.get("offset", [0, 0])
	home.offset = Vector2(float(offset[0]), float(offset[1])) if offset.size() >= 2 else Vector2.ZERO
	home.garage_slots = int(data.get("garage_slots", 1))
	home.unlock_flag = StringName(data.get("unlock_flag", ""))
	home.price = float(data.get("price", 0.0))
	home.description = String(data.get("description", ""))
	var rooms: Array[Dictionary] = []
	for room: Variant in data.get("rooms", []):
		rooms.append(room as Dictionary)
	home.rooms = rooms
	return home


static func all() -> Array[Home]:
	ensure_loaded()
	return _homes


static func get_by_id(id: StringName) -> Home:
	ensure_loaded()
	return _by_id.get(id)


static func at_settlement(settlement: StringName) -> Array[Home]:
	ensure_loaded()
	var out: Array[Home] = []
	for home: Home in _homes:
		if home.settlement == settlement:
			out.append(home)
	return out


static func owned() -> Array[Home]:
	ensure_loaded()
	var out: Array[Home] = []
	for home: Home in _homes:
		if home.is_owned():
			out.append(home)
	return out


## Открывает дом. Именно открывает, а не дарит: купить его после этого всё
## равно придётся, если у него есть цена.
static func unlock(id: StringName) -> bool:
	var home := get_by_id(id)
	if home == null:
		return false
	if home.unlock_flag != &"":
		GameState.set_flag(home.unlock_flag, true)
	if home.price <= 0.0:
		return give(id)
	EventBus.notify("Открыт дом: %s" % home.name)
	return true


## Отдаёт дом без денег. Так выдают ключ от бокса на заставе.
static func give(id: StringName) -> bool:
	var home := get_by_id(id)
	if home == null or home.is_owned():
		return false
	GameState.set_flag(StringName("home_owned_%s" % id), true)
	EventBus.notify("Теперь ваш: %s" % home.name)
	return true


static func buy(id: StringName) -> bool:
	var home := get_by_id(id)
	if home == null:
		return false
	if home.is_owned():
		return false
	if not home.is_available():
		EventBus.notify("Этот дом пока не продаётся", &"warning")
		return false
	if not GameState.spend(home.price):
		EventBus.notify("Не хватает денег", &"warning")
		return false
	GameState.set_flag(StringName("home_owned_%s" % id), true)
	EventBus.notify("Куплен дом: %s" % home.name)
	return true


# --- Гараж ------------------------------------------------------------------


## Машины, стоящие в гараже дома. Хранятся в состоянии прохождения, а не в
## сцене: гараж в Айн-Дибе должен помнить свою машину, пока вы в Хуфре.
static func stored(id: StringName) -> Array[StringName]:
	var raw: Variant = GameState.flag(StringName("garage_%s" % id), [])
	var out: Array[StringName] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item: Variant in raw as Array:
		out.append(StringName(item))
	return out


static func free_slots(id: StringName) -> int:
	var home := get_by_id(id)
	if home == null:
		return 0
	return maxi(home.garage_slots - stored(id).size(), 0)


## Ставит машину в гараж. Возвращает false, если мест нет — и это не
## формальность: гараж на одну машину и есть причина искать второй дом.
static func store(id: StringName, vehicle_id: StringName) -> bool:
	var home := get_by_id(id)
	if home == null or not home.is_owned():
		return false
	var list := stored(id)
	if list.size() >= home.garage_slots:
		EventBus.notify("В гараже нет места", &"warning")
		return false
	if list.has(vehicle_id):
		return false
	list.append(vehicle_id)
	_write(id, list)
	return true


static func take(id: StringName, vehicle_id: StringName) -> bool:
	var list := stored(id)
	if not list.has(vehicle_id):
		return false
	list.erase(vehicle_id)
	_write(id, list)
	return true


static func _write(id: StringName, list: Array[StringName]) -> void:
	var plain: Array = []
	for item: StringName in list:
		plain.append(String(item))
	GameState.set_flag(StringName("garage_%s" % id), plain)


## Где сейчас стоит названная машина, если она в каком-то гараже.
static func where_is(vehicle_id: StringName) -> StringName:
	ensure_loaded()
	for home: Home in _homes:
		if stored(home.id).has(vehicle_id):
			return home.id
	return &""
