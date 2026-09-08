extends Node
## Кольцевой буфер измерений с выгрузкой в CSV.
##
## Нужен в двух местах: отладочный оверлей в игре и стенд `tools/bench_vehicle.gd`,
## который гоняет машину без окна и печатает графики разгона и сноса. Один и тот
## же код пишет данные в обоих случаях, поэтому цифры на экране и цифры в отчёте
## заведомо совпадают.

const CAPACITY := 4096

var enabled: bool = false

var _columns: PackedStringArray = PackedStringArray()
var _rows: Array[PackedFloat32Array] = []
var _head: int = 0
var _count: int = 0
var _scalars: Dictionary[StringName, float] = {}


func begin(columns: PackedStringArray) -> void:
	_columns = columns
	_rows.clear()
	_rows.resize(CAPACITY)
	_head = 0
	_count = 0
	enabled = true


func stop() -> void:
	enabled = false


func push(values: PackedFloat32Array) -> void:
	if not enabled:
		return
	if values.size() != _columns.size():
		push_warning("Telemetry: ожидалось %d колонок, пришло %d" % [_columns.size(), values.size()])
		return
	_rows[_head] = values
	_head = (_head + 1) % CAPACITY
	_count = mini(_count + 1, CAPACITY)


## Мгновенные значения для оверлея — их не пишут в историю, только показывают.
func set_scalar(key: StringName, value: float) -> void:
	_scalars[key] = value


func scalar(key: StringName, fallback: float = 0.0) -> float:
	return _scalars.get(key, fallback)


func scalars() -> Dictionary[StringName, float]:
	return _scalars


func sample_count() -> int:
	return _count


## Значения одной колонки по порядку записи, от старого к новому.
func column(name: String) -> PackedFloat32Array:
	var index := _columns.find(name)
	var out := PackedFloat32Array()
	if index == -1:
		return out
	out.resize(_count)
	var start := (_head - _count + CAPACITY) % CAPACITY
	for i: int in _count:
		out[i] = _rows[(start + i) % CAPACITY][index]
	return out


func to_csv() -> String:
	var lines := PackedStringArray()
	lines.append(",".join(_columns))
	var start := (_head - _count + CAPACITY) % CAPACITY
	for i: int in _count:
		var row := _rows[(start + i) % CAPACITY]
		var cells := PackedStringArray()
		for value: float in row:
			cells.append("%.5f" % value)
		lines.append(",".join(cells))
	return "\n".join(lines)


func write_csv(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Telemetry: не записать %s" % path)
		return false
	file.store_string(to_csv())
	file.close()
	return true
