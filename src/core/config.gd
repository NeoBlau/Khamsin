extends Node
## Единая точка правды по числам, которые балансируются, а не выводятся.
##
## Всё, что здесь лежит, читается кодом через `Config.X`. Значения, которые
## дизайнер может менять без пересборки, дополнительно перекрываются файлом
## `res://data/balance.json` — он грузится при старте и накрывает поля с теми же
## именами. Если файла нет, работают значения по умолчанию отсюда.

const VERSION := "0.1.0"
const SAVE_FORMAT_VERSION := 3

# --- Мир -------------------------------------------------------------------

## Полуразмер игрового мира в метрах. Карта — квадрат 2*WORLD_EXTENT со стороной
## 20 км: за границей начинается непроходимый эрг и машину разворачивает.
var world_extent: float = 10000.0
## Размер чанка ландшафта в метрах.
var chunk_size: float = 256.0
## Радиус загрузки чанков вокруг игрока, в чанках. 8 → квадрат 17x17, 4.3 км.
var chunk_view_radius: int = 8
## В скольких чанках вокруг игрока строится коллизия. 1 → кольцо 3x3, 768 м.
var chunk_collision_radius: int = 1
## Шаг сетки коллизии в метрах. Меньше — точнее подвеска, дороже память.
var collision_cell: float = 2.0
## Число делений визуального меша по LOD, от ближнего к дальнему.
var lod_divisions: Array[int] = [64, 32, 16, 8, 8, 4]
## Дистанции переключения LOD в метрах.
var lod_distances: Array[float] = [320.0, 700.0, 1400.0, 2600.0, 4000.0]

# --- Рельеф ----------------------------------------------------------------

## Высота дюн от подошвы до гребня, метры.
var dune_amplitude: float = 32.0
## Длина волны дюнного поля, метры. Реальные линейные дюны — 200-2000 м.
var dune_wavelength: float = 380.0
## Направление господствующего ветра (и, значит, ориентация дюн), радианы.
var dune_wind_angle: float = 0.62
## Доля периода дюны, приходящаяся на пологий наветренный склон.
var dune_windward_fraction: float = 0.72
## Амплитуда крупного рельефа — плато, впадины, гряды.
var macro_amplitude: float = 120.0
## Радиус, в котором поселение выравнивает под собой землю, метры.
var settlement_flatten_radius: float = 260.0
## Полуширина накатанной колеи, метры.
var track_half_width: float = 11.0

# --- Симуляция -------------------------------------------------------------

## Плотность воздуха, кг/м³. При +45 °C в пустыне заметно ниже стандартных 1.225.
var air_density: float = 1.12
## Ускорение свободного падения, м/с².
var gravity: float = 9.81

# --- Экономика -------------------------------------------------------------

var starting_money: float = 4200.0
var fuel_price_per_litre: float = 1.35
## Наценка на топливо в удалённых посёлках, множитель к базовой цене.
var remote_fuel_markup: float = 1.9
## Ставка за километр по прямой, база для генератора контрактов.
var contract_rate_per_km: float = 9.0
## Доля от объявленной стоимости груза, которая идёт в оплату перевозки.
var contract_value_rate: float = 0.08
## Залог как доля от стоимости груза. Он должен быть заметным, но заведомо
## меньше гонорара, иначе брать заказ невыгодно даже при идеальной доставке.
var contract_deposit_rate: float = 0.05
## Штраф за просрочку — доля от гонорара за каждый час опоздания.
var late_penalty_per_hour: float = 0.18
## Цена нормо-часа в мастерской.
var repair_labour_rate: float = 90.0

# --- Время -----------------------------------------------------------------

## Сколько реальных секунд длится игровой час на обычной скорости.
var seconds_per_game_hour: float = 90.0
var start_hour: float = 6.5

# --- Ощущения ---------------------------------------------------------------

## Продольная перегрузка, выше которой хрупкий груз начинает биться, в g.
var cargo_shock_threshold_g: float = 2.6
## Множитель урона грузу от перегрузки сверх порога.
var cargo_shock_scale: float = 0.055

const BALANCE_PATH := "res://data/balance.json"


func _ready() -> void:
	_load_overrides()


## Накрывает поля значениями из balance.json. Неизвестные ключи и несовпадающие
## типы игнорируются с предупреждением — правка данных не должна ронять игру.
func _load_overrides() -> void:
	if not FileAccess.file_exists(BALANCE_PATH):
		return
	var text := FileAccess.get_file_as_string(BALANCE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("balance.json: ожидался объект, получено %s" % type_string(typeof(parsed)))
		return
	for key: String in (parsed as Dictionary).keys():
		if not key in self:
			push_warning("balance.json: неизвестный ключ '%s'" % key)
			continue
		var current: Variant = get(key)
		var incoming: Variant = (parsed as Dictionary)[key]
		# JSON не различает int и float, поэтому числа приводим к типу поля.
		if typeof(current) == TYPE_FLOAT and typeof(incoming) == TYPE_INT:
			incoming = float(incoming)
		elif typeof(current) == TYPE_INT and typeof(incoming) == TYPE_FLOAT:
			incoming = int(incoming)
		if typeof(current) != typeof(incoming):
			push_warning("balance.json: '%s' ожидает %s" % [key, type_string(typeof(current))])
			continue
		set(key, incoming)


## Полный размер мира по стороне, метры.
func world_size() -> float:
	return world_extent * 2.0
