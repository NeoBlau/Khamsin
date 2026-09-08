extends Node
## Детерминированная случайность.
##
## Правило проекта: ни один игровой объект не зовёт `randi()` напрямую. Всё
## идёт либо через именованный поток `Rng.stream("contracts")`, либо через
## чистые хеш-функции от координат. Тогда мир с одинаковым сидом собирается
## одинаково на любой машине, а сейв можно хранить как «сид + список отличий».

# splitmix64-константы. GDScript не принимает hex-литералы старше int64.max,
# поэтому записаны знаковыми десятичными: 0x9E3779B97F4A7C15, 0xBF58476D1CE4E5B9,
# 0x94D049BB133111EB соответственно.
const MIX_A := -7046029254386353131
const MIX_B := -4658895280553007687
const MIX_C := -7723592293110705685
## 0xCBF29CE484222325 — стартовое значение FNV-1a.
const FNV_OFFSET := -3750763034362895579
const FNV_PRIME := 1099511628211

var world_seed: int = 0x5EEDCAFE

var _streams: Dictionary[String, RandomNumberGenerator] = {}


func set_world_seed(value: int) -> void:
	world_seed = value
	_streams.clear()


## Именованный поток. Один и тот же вызов всегда возвращает один и тот же
## генератор, поэтому последовательность зависит от порядка обращений внутри
## подсистемы, но не от других подсистем.
func stream(name: String) -> RandomNumberGenerator:
	var existing: RandomNumberGenerator = _streams.get(name)
	if existing != null:
		return existing
	var rng := RandomNumberGenerator.new()
	rng.seed = mix(world_seed, hash_string(name))
	_streams[name] = rng
	return rng


## Свежий генератор, не привязанный к кешу потоков. Нужен там, где результат
## обязан зависеть только от переданных чисел (генерация чанка в потоке).
func local(a: int, b: int = 0, c: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = mix(mix(world_seed, a), mix(b, c))
	return rng


## splitmix64. Быстро, без состояния, хорошо перемешивает соседние значения —
## именно то, что нужно для «шума от координат».
func mix(a: int, b: int) -> int:
	var x: int = a + MIX_A * (b | 1)
	x = (x ^ ushr(x, 30)) * MIX_B
	x = (x ^ ushr(x, 27)) * MIX_C
	return x ^ ushr(x, 31)


## Логический сдвиг вправо. У GDScript `>>` арифметический, он тянет знаковый
## бит и вдвое роняет качество перемешивания на отрицательных значениях.
static func ushr(value: int, bits: int) -> int:
	if bits <= 0:
		return value
	return (value >> bits) & ((1 << (64 - bits)) - 1)


func hash_string(text: String) -> int:
	var h: int = FNV_OFFSET
	for i: int in text.length():
		h = (h ^ text.unicode_at(i)) * FNV_PRIME
	return h


## Число в [0, 1) от целочисленных координат. Ни состояния, ни аллокаций.
func unit(a: int, b: int = 0, c: int = 0) -> float:
	var h: int = mix(mix(world_seed, a), mix(b, c))
	return float(h & 0xFFFFFFFFFF) / 1099511627776.0


func range_from(a: int, b: int, c: int, low: float, high: float) -> float:
	return low + unit(a, b, c) * (high - low)


func pick(items: Array, rng: RandomNumberGenerator) -> Variant:
	if items.is_empty():
		return null
	return items[rng.randi_range(0, items.size() - 1)]


## Взвешенный выбор. `weights` должен быть той же длины, что и `items`.
func pick_weighted(items: Array, weights: PackedFloat32Array, rng: RandomNumberGenerator) -> Variant:
	if items.is_empty():
		return null
	var total: float = 0.0
	for w: float in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return pick(items, rng)
	var roll: float = rng.randf() * total
	for i: int in items.size():
		roll -= maxf(weights[i], 0.0)
		if roll <= 0.0:
			return items[i]
	return items[items.size() - 1]
