class_name VehicleCamera
extends Camera3D
## Камера за машиной.
##
## Три вещи, из-за которых камера в автосимуляторе ощущается дешёвой: она
## жёстко приклеена к кузову, она не смотрит туда, куда машина едет, и она
## одинаково ведёт себя на десяти и на ста километрах в час. Здесь всё три
## решаются пружиной с разной жёсткостью по осям, упреждением по скорости и
## полем зрения, растущим с разгоном.

enum Mode { CHASE, HOOD, ORBIT }

const MODE_NAMES: Dictionary[Mode, String] = {
	Mode.CHASE: "снаружи",
	Mode.HOOD: "из кабины",
	Mode.ORBIT: "облёт",
}

@export var mode: Mode = Mode.CHASE
@export var distance: float = 9.0
@export var height: float = 3.4
## Насколько сильно камера смотрит вперёд по вектору скорости.
@export var lead: float = 0.55
@export var base_fov: float = 72.0
## Прибавка к полю зрения на предельной скорости — ощущение разгона.
@export var speed_fov: float = 14.0

var target: VehicleBody

var _position: Vector3 = Vector3.ZERO
var _look_at: Vector3 = Vector3.ZERO
var _orbit_angle: float = 0.0
var _free_look: Vector2 = Vector2.ZERO
var _initialised: bool = false


func _ready() -> void:
	current = true
	near = 0.15
	far = 6000.0
	fov = base_fov


func follow(vehicle: VehicleBody) -> void:
	target = vehicle
	_initialised = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_action_pressed(&"free_look"):
		var motion := event as InputEventMouseMotion
		_free_look.x -= motion.relative.x * Settings.mouse_sensitivity * 0.01
		var vertical := motion.relative.y * Settings.mouse_sensitivity * 0.01
		_free_look.y += -vertical if Settings.invert_look_y else vertical
		_free_look.y = clampf(_free_look.y, -0.6, 1.0)
	elif event.is_action_pressed(&"camera_cycle"):
		cycle_mode()


func cycle_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
	_initialised = false
	EventBus.notify("Камера: %s" % MODE_NAMES[mode])


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not Input.is_action_pressed(&"free_look"):
		_free_look = _free_look.lerp(Vector2.ZERO, 1.0 - exp(-4.0 * delta))

	match mode:
		Mode.HOOD:
			_update_hood(delta)
		Mode.ORBIT:
			_update_orbit(delta)
		_:
			_update_chase(delta)

	fov = lerpf(fov, base_fov + speed_fov * clampf(target.speed / 32.0, 0.0, 1.0), 1.0 - exp(-3.0 * delta))


func _update_chase(delta: float) -> void:
	var xform := target.global_transform
	var forward := -xform.basis.z
	var velocity := target.linear_velocity
	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)

	# Смотрим не в машину, а в точку впереди неё. На скорости она уезжает
	# дальше, и в повороте камера начинает вести, а не догонять.
	var look_ahead := flat_velocity * lead
	var desired_look := xform.origin + Vector3.UP * 1.2 + look_ahead.limit_length(18.0)

	# Позади машины — но по направлению движения, а не кузова: в заносе видно,
	# куда её несёт.
	var behind := forward
	if flat_velocity.length() > 3.0:
		behind = behind.lerp(flat_velocity.normalized(), 0.55).normalized()
	behind = behind.rotated(Vector3.UP, _free_look.x)

	var lift := height + _free_look.y * 4.0 + clampf(target.speed * 0.03, 0.0, 1.2)
	var desired := xform.origin - behind * distance + Vector3.UP * lift
	desired = _avoid_ground(xform.origin + Vector3.UP * 1.2, desired)

	if not _initialised:
		_position = desired
		_look_at = desired_look
		_initialised = true
	# Пружина по позиции мягче, чем по точке взгляда: так камера отстаёт при
	# разгоне, но не мажет мимо машины.
	_position = _position.lerp(desired, 1.0 - exp(-5.0 * delta))
	_look_at = _look_at.lerp(desired_look, 1.0 - exp(-9.0 * delta))

	global_position = _position
	if _position.distance_squared_to(_look_at) > 0.01:
		look_at(_look_at, _roll_up(delta))


func _update_hood(delta: float) -> void:
	var xform := target.global_transform
	var offset := Vector3(-0.42, target.config.body_size.y * 0.62, -target.config.body_size.z * 0.16)
	global_transform = Transform3D(
		xform.basis * Basis(Vector3.UP, _free_look.x) * Basis(Vector3.RIGHT, -_free_look.y * 0.6),
		xform * offset
	)
	_initialised = false
	# Тряска кабины: чем хуже дорога, тем сильнее. Считаем по ходу подвески,
	# а не случайным шумом — на асфальте её честно нет.
	var jolt := 0.0
	for wheel: VehicleWheel in target.wheels:
		jolt = maxf(jolt, absf(wheel.compression_velocity))
	var shake := clampf(jolt * 0.004, 0.0, 0.03)
	rotate_object_local(Vector3.RIGHT, randf_range(-shake, shake))
	rotate_object_local(Vector3.UP, randf_range(-shake, shake) * 0.5)


func _update_orbit(delta: float) -> void:
	_orbit_angle += delta * 0.25
	var centre := target.global_position + Vector3.UP * 1.4
	var offset := Vector3(cos(_orbit_angle), 0.0, sin(_orbit_angle)) * (distance * 1.6)
	global_position = centre + offset + Vector3.UP * (height + 2.0)
	look_at(centre, Vector3.UP)


## Крен камеры вслед за боковым ускорением. Небольшой — большой вызывает
## морскую болезнь, но без него повороты выглядят стерильно.
func _roll_up(delta: float) -> Vector3:
	var lateral := clampf(target.lateral_speed * 0.02, -0.6, 0.6)
	var right := target.global_transform.basis.x
	return (Vector3.UP + right * lateral * 0.12).normalized()


## Не даёт камере уехать под землю или в скалу.
func _avoid_ground(from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return to
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [target.get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return to
	var point: Vector3 = hit["position"]
	return from + (point - from) * 0.85 + Vector3.UP * 0.3
