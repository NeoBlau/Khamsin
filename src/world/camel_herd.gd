class_name CamelHerd
extends Node3D
## Стада верблюдов на карте.
##
## Верблюды не расставлены руками и не появляются из воздуха перед капотом.
## Места стоянок выводятся из сида — те же детерминированные потоки, что и у
## мира: одно и то же стадо всегда в одном и том же месте, и вернуться к нему
## можно. Живыми узлами становятся только ближние стада, остальные существуют
## как две координаты в списке.
##
## Стоят они там, где стояли бы на самом деле: у воды, у поселений и вдоль
## накатанных дорог. Посреди эрга верблюду делать нечего, и если он там есть —
## значит кто-то его туда привёл, а это уже сюжет.

const HERD_COUNT := 26
const SPAWN_RADIUS := 210.0
const DESPAWN_RADIUS := 300.0
## Больше трёх стад одновременно в кадре не бывает, а нарисованы они из
## двух десятков панелей каждый — предел нужен, иначе у поселения, где стада
## стоят кучно, в сцене оказывается полсотни верблюдов.
const MAX_LIVE_HERDS := 3
const MIN_HERD := 2
const MAX_HERD := 7

var target: Node3D

var _places: Array[Dictionary] = []
var _live: Dictionary = {}
var _poll: float = 0.0


func begin(follow: Node3D) -> void:
	target = follow
	_plan_places()
	set_process(true)


## Где стоят стада. Считается один раз на сид.
func _plan_places() -> void:
	_places.clear()
	# Именно local(), а не stream(): именованный поток кеширует генератор
	# вместе с его состоянием, и второй вызов на том же сиде даёт другую
	# раскладку. Стада бы «переезжали» после возврата в меню и обратно.
	var rng := Rng.local(Rng.hash_string("camels"))
	var settlements := World.settlements
	for i: int in HERD_COUNT:
		var spot := Vector2.ZERO
		if not settlements.is_empty() and i % 3 != 2:
			# Две трети стад — у поселений: там вода и там их пасут.
			var settlement: Settlement = settlements[rng.randi_range(0, settlements.size() - 1)]
			var angle := rng.randf() * TAU
			var distance := rng.randf_range(90.0, 420.0)
			spot = settlement.position + Vector2(cos(angle), sin(angle)) * distance
		else:
			var half := Config.world_size() * 0.5 - 600.0
			spot = Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		_places.append({
			"at": spot,
			"size": rng.randi_range(MIN_HERD, MAX_HERD),
			"seed": rng.randi(),
		})


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.7
	var here := Vector2(target.global_position.x, target.global_position.z)
	for i: int in _places.size():
		var place: Dictionary = _places[i]
		var distance: float = (place["at"] as Vector2).distance_to(here)
		if distance < SPAWN_RADIUS and not _live.has(i) and _live.size() < MAX_LIVE_HERDS:
			_spawn(i, place)
		elif distance > DESPAWN_RADIUS and _live.has(i):
			_despawn(i)


func _spawn(index: int, place: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(place["seed"])
	var centre: Vector2 = place["at"]
	var herd: Array[Camel] = []
	for i: int in int(place["size"]):
		var offset := Vector2(rng.randfn(0.0, 11.0), rng.randfn(0.0, 11.0))
		var x := centre.x + offset.x
		var z := centre.y + offset.y
		var camel := Camel.new()
		add_child(camel)
		camel.setup(Vector3(x, World.height(x, z), z), rng.randi())
		camel.wander_radius = 26.0 + rng.randf() * 22.0
		herd.append(camel)
	_live[index] = herd


func _despawn(index: int) -> void:
	for camel: Camel in _live[index]:
		if is_instance_valid(camel):
			camel.queue_free()
	_live.erase(index)


## Сколько верблюдов сейчас живыми узлами. Нужно тестам и отладке.
func live_count() -> int:
	var total := 0
	for index: int in _live:
		total += (_live[index] as Array).size()
	return total


func herd_places() -> Array[Dictionary]:
	return _places
