class_name CamelSpit
extends Node3D
## Плевок в полёте.
##
## Летит по баллистической дуге с упреждением: верблюд целится не туда, где
## машина сейчас, а туда, где она будет. Промахнуться он всё-таки может — если
## успеть дать газу или свернуть, плевок уйдёт в песок. Это единственная
## защита, и она честная.

const SPEED := 16.0
const LIFETIME := 4.0
const HIT_RADIUS := 2.6

var velocity: Vector3 = Vector3.ZERO
var target: Node3D
var source: Node3D

var _age: float = 0.0
var _trail: Array[Vector3] = []


func launch(from: Vector3, at: Node3D, by: Node3D) -> void:
	global_position = from
	target = at
	source = by
	velocity = _aim(from, at)


func _ready() -> void:
	name = "CamelSpit"
	var blob := MeshFactory.panel(Vector3(0.14, 0.11, 0.16), Color(0.72, 0.76, 0.58), 0.25, 0.0, 0.05)
	add_child(blob)
	set_physics_process(true)


## Упреждение: решаем, куда машина уедет за время полёта, и стреляем туда.
## Одна итерация уточнения — этого достаточно, верблюд не артиллерист.
func _aim(from: Vector3, at: Node3D) -> Vector3:
	if at == null:
		return Vector3.FORWARD * SPEED
	var lead := Vector3.ZERO
	if at is VehicleBody:
		lead = (at as VehicleBody).linear_velocity
	var to_target := at.global_position + Vector3.UP * 0.9 - from
	var flight := clampf(to_target.length() / SPEED, 0.1, 2.0)
	var aim_point := at.global_position + Vector3.UP * 0.9 + lead * flight
	var offset := aim_point - from
	# Компенсация падения за время полёта.
	offset.y += 0.5 * 9.81 * flight * flight
	return offset.normalized() * SPEED


func _physics_process(delta: float) -> void:
	_age += delta
	velocity.y -= 9.81 * delta
	global_position += velocity * delta
	_trail.append(global_position)

	if target != null and is_instance_valid(target):
		var distance := global_position.distance_to(target.global_position)
		if distance < HIT_RADIUS:
			_hit(target)
			return
	# Упал на землю — промах.
	if global_position.y < World.height(global_position.x, global_position.z) - 0.2:
		queue_free()
		return
	if _age > LIFETIME:
		queue_free()


func _hit(body: Node3D) -> void:
	var grime: Grime = null
	for child: Node in body.get_children():
		if child is Grime:
			grime = child as Grime
	if grime != null:
		var local := body.to_local(global_position)
		# Прижимаем кляксу к обшивке: летящий плевок попал куда-то в габарит,
		# а прилипнуть должен снаружи, а не повиснуть внутри кузова.
		grime.add_splat(_to_shell(body, local), randf_range(0.7, 1.3))
	queue_free()


## Ближайшая точка на поверхности габаритной коробки кузова.
static func _to_shell(body: Node3D, local: Vector3) -> Vector3:
	var size := Vector3(1.0, 1.0, 2.0)
	if body is VehicleBody:
		var config := (body as VehicleBody).config
		size = config.body_size * 0.5
		local -= config.body_offset
	var scaled := Vector3(
		absf(local.x) / maxf(size.x, 0.001),
		absf(local.y) / maxf(size.y, 0.001),
		absf(local.z) / maxf(size.z, 0.001)
	)
	var on := local
	# Выталкиваем по той оси, по которой ближе всего к грани.
	if scaled.x >= scaled.y and scaled.x >= scaled.z:
		on.x = signf(local.x) * size.x
	elif scaled.y >= scaled.z:
		on.y = signf(local.y) * size.y
	else:
		on.z = signf(local.z) * size.z
	if body is VehicleBody:
		on += (body as VehicleBody).config.body_offset
	return on
