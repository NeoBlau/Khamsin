class_name Settlement
extends RefCounted
## Точка на карте, где можно что-то сделать: заправиться, починиться, взять груз.

enum Kind { CITY, OASIS, OUTPOST, WELL, MINE, STATION, CAMP, FARM, RUIN }

const KIND_NAMES: Dictionary[String, Kind] = {
	"city": Kind.CITY,
	"oasis": Kind.OASIS,
	"outpost": Kind.OUTPOST,
	"well": Kind.WELL,
	"mine": Kind.MINE,
	"station": Kind.STATION,
	"camp": Kind.CAMP,
	"farm": Kind.FARM,
	"ruin": Kind.RUIN,
}

var id: StringName = &""
var display_name: String = ""
var description: String = ""
var kind: Kind = Kind.OUTPOST
## Положение в плане, метры. Высота берётся из рельефа при сборке мира.
var position: Vector2 = Vector2.ZERO
## Радиус выровненной площадки и заодно радиус «я приехал».
var radius: float = 220.0
var faction: StringName = &"guild"
var services: Array[StringName] = []
## Множитель к цене топлива. В глуши солярку возят бочками, и это видно в счёте.
var fuel_markup: float = 1.0
## Насколько бойкая биржа: сколько заказов висит на доске одновременно.
var contract_slots: int = 3
## Высота площадки над нулём. Заполняется при сборке мира из рельефа.
var ground_height: float = 0.0
## Открыт ли посёлок с начала игры или его надо найти.
var known_from_start: bool = false


func has_service(service: StringName) -> bool:
	return services.has(service)


func world_position() -> Vector3:
	return Vector3(position.x, ground_height, position.y)


func kind_name() -> String:
	match kind:
		Kind.CITY: return "город"
		Kind.OASIS: return "оазис"
		Kind.OUTPOST: return "застава"
		Kind.WELL: return "колодец"
		Kind.MINE: return "карьер"
		Kind.STATION: return "станция"
		Kind.CAMP: return "лагерь"
		Kind.FARM: return "ферма"
		_: return "руины"


static func from_dict(data: Dictionary) -> Settlement:
	var s := Settlement.new()
	s.id = StringName(data.get("id", ""))
	s.display_name = String(data.get("name", data.get("id", "")))
	s.description = String(data.get("description", ""))
	s.kind = KIND_NAMES.get(String(data.get("kind", "outpost")), Kind.OUTPOST)
	var pos: Array = data.get("position", [0, 0])
	s.position = Vector2(float(pos[0]), float(pos[1])) if pos.size() >= 2 else Vector2.ZERO
	s.radius = float(data.get("radius", 220.0))
	s.faction = StringName(data.get("faction", "guild"))
	s.fuel_markup = float(data.get("fuel_markup", 1.0))
	s.contract_slots = int(data.get("contract_slots", 3))
	s.known_from_start = bool(data.get("known", false))
	var services: Array[StringName] = []
	for service: Variant in data.get("services", []):
		services.append(StringName(service))
	s.services = services
	return s
