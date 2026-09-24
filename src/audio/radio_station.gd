class_name RadioStation
extends RefCounted
## Описание станции: что она играет, кто её ведёт и откуда вещает.
##
## Станция — не плейлист, а набор правил. Ладов и ритмов у неё несколько,
## конкретный трек собирается при выходе в эфир, поэтому дважды одно и то же
## не звучит. Передатчик стоит в точке на карте: чем дальше, тем больше помех,
## и это единственный способ потерять волну — крутилка ни при чём.

var id: StringName = &"khamsin"
var name: String = "Хамсин FM"
var frequency: float = 88.3
var scales: Array[StringName] = [&"bayati"]
var rhythms: Array[StringName] = [&"maqsum"]
var leads: Array[StringName] = [&"oud"]
var tempo_range: Vector2 = Vector2(80.0, 100.0)
var host: StringName = &"radio_host"
## Точка вещания. Пустая — станция слышна везде одинаково.
var transmitter: Vector2 = Vector2.ZERO
var range_km: float = 1000.0
## Часы, в которые станция в эфире. Пусто — круглосуточно.
var hours: Vector2 = Vector2.ZERO
var talk_chance: float = 0.34
var advert_chance: float = 0.2
var warmth: float = 0.35
var talk_lines: PackedStringArray = PackedStringArray()
var advert_lines: PackedStringArray = PackedStringArray()
var station_id_lines: PackedStringArray = PackedStringArray()
## Станция открывается по сюжету, а не с самого начала.
var requires_flag: StringName = &""


func on_air_at(hour: float) -> bool:
	if hours.x == hours.y:
		return true
	if hours.x < hours.y:
		return hour >= hours.x and hour < hours.y
	# Ночная станция: интервал пересекает полночь.
	return hour >= hours.x or hour < hours.y


## Качество приёма от нуля до единицы. Ноль — сплошные помехи.
func reception(at: Vector2) -> float:
	if range_km >= 999.0:
		return 1.0
	var distance := at.distance_to(transmitter) / 1000.0
	# До двух третей радиуса — чисто, дальше быстро уходит в шум.
	var clean := range_km * 0.62
	if distance <= clean:
		return 1.0
	var fade := (distance - clean) / maxf(range_km - clean, 0.001)
	# За краем радиуса приём не ноль, а «почти»: полностью немой эфир звучит
	# как поломка игры, а не как далёкая станция.
	return clampf(1.0 - fade, 0.04, 1.0)


func pick_tempo(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(tempo_range.x, tempo_range.y)


func pick_scale(rng: RandomNumberGenerator) -> StringName:
	return scales[rng.randi_range(0, scales.size() - 1)]


func pick_rhythm(rng: RandomNumberGenerator) -> StringName:
	return rhythms[rng.randi_range(0, rhythms.size() - 1)]


func pick_lead(rng: RandomNumberGenerator) -> StringName:
	return leads[rng.randi_range(0, leads.size() - 1)]
