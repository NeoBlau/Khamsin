class_name Walker
extends CharacterBody3D
## Игрок на ногах.
##
## Пешая часть здесь не отдельная игра, а способ дотянуться до того, до чего
## из кабины не дотянуться: зайти в дом, заглянуть под машину, отмыть плевок,
## подойти к верблюду ближе, чем стоило бы.
##
## Поэтому контроллер намеренно простой и предсказуемый. Никакой инерции
## скольжения, никакого разгона на полсекунды: пустыня и так достаточно
## медленная, чтобы ещё и ходьба сопротивлялась.

signal wants_to_enter_vehicle()

const WALK_SPEED := 2.4
const RUN_SPEED := 5.2
const ACCELERATION := 14.0
const FRICTION := 18.0
const JUMP_SPEED := 4.0
const EYE_HEIGHT := 1.62
const RADIUS := 0.32
const HEIGHT := 1.78
## Крутизна, выше которой уже не идут, а сползают.
const MAX_SLOPE_DEG := 48.0
## Скорость проседания шага в песке. Глубина берётся из того же покрытия, что
## и просадка колёс: по рыхлому песку человек идёт медленнее, и это та же
## физика, а не отдельное число.
const SAND_DRAG := 0.45

@export var mouse_sensitivity_scale: float = 1.0

var head: Node3D
var camera: Camera3D
var can_move: bool = true

var _yaw: float = 0.0
var _pitch: float = 0.0
var _step_distance: float = 0.0
var _body: Node3D
var _footstep: AudioStreamPlayer3D
var _footstep_cache: Dictionary = {}


func _ready() -> void:
	name = "Walker"
	add_to_group(&"player_walker")
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_max_angle = deg_to_rad(MAX_SLOPE_DEG)
	# Небольшая «прилипчивость» к земле: без неё человек отрывается на каждом
	# гребне ряби и идёт прыжками.
	floor_snap_length = 0.4
	slide_on_ceiling = false

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(shape)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	add_child(head)

	camera = Camera3D.new()
	camera.name = "Eye"
	camera.near = 0.08
	camera.far = 4000.0
	camera.fov = Settings.fov
	head.add_child(camera)

	_build_body()

	_footstep = AudioStreamPlayer3D.new()
	_footstep.bus = &"World"
	_footstep.max_distance = 22.0
	add_child(_footstep)

	set_physics_process(true)


## Тело видно только в зеркале и на снимках, но без него игрок — парящая
## камера, и это видно по тени: она есть у всего, кроме него.
func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var cloth := Color(0.78, 0.74, 0.62)
	var skin := Color(0.52, 0.38, 0.27)

	var robe := MeshFactory.panel(Vector3(0.46, 1.05, 0.28), cloth, 0.95, 0.0, 0.06)
	robe.position = Vector3(0.0, 0.62, 0.0)
	_body.add_child(robe)

	var chest := MeshFactory.panel(Vector3(0.44, 0.34, 0.26), cloth.darkened(0.06), 0.95, 0.0, 0.05)
	chest.position = Vector3(0.0, 1.30, 0.0)
	_body.add_child(chest)

	var head_mesh := MeshFactory.panel(Vector3(0.20, 0.24, 0.20), skin, 0.9, 0.0, 0.05)
	head_mesh.position = Vector3(0.0, 1.58, 0.0)
	_body.add_child(head_mesh)

	# Куфия: в пустыне без головного убора не ходят, и силуэт без неё читается
	# как человек не отсюда.
	var scarf := MeshFactory.panel(Vector3(0.26, 0.16, 0.26), Color(0.88, 0.86, 0.80), 0.95, 0.0, 0.05)
	scarf.position = Vector3(0.0, 1.70, 0.0)
	_body.add_child(scarf)

	for side: int in 2:
		var arm_sign := 1.0 if side == 0 else -1.0
		var arm := MeshFactory.panel(Vector3(0.12, 0.62, 0.14), cloth, 0.95, 0.0, 0.04)
		arm.position = Vector3(arm_sign * 0.28, 1.06, 0.0)
		_body.add_child(arm)


func place_at(xform: Transform3D) -> void:
	global_transform = Transform3D(Basis.IDENTITY, xform.origin)
	_yaw = xform.basis.get_euler().y
	_pitch = 0.0
	velocity = Vector3.ZERO
	_apply_look()


func activate(active: bool) -> void:
	visible = active
	can_move = active
	set_physics_process(active)
	camera.current = active
	# Тело собственного персонажа не должно закрывать обзор от первого лица.
	_body.visible = false


func eye_position() -> Vector3:
	return head.global_position


func facing() -> Vector3:
	return -head.global_transform.basis.z


func _unhandled_input(event: InputEvent) -> void:
	if not can_move:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var sensitivity := Settings.mouse_sensitivity * 0.01 * mouse_sensitivity_scale
		_yaw -= motion.relative.x * sensitivity
		var vertical := motion.relative.y * sensitivity
		_pitch += -vertical if Settings.invert_look_y else vertical
		_pitch = clampf(_pitch, -1.45, 1.45)
		_apply_look()
	elif event.is_action_pressed(&"exit_vehicle"):
		wants_to_enter_vehicle.emit()


func _apply_look() -> void:
	rotation = Vector3(0.0, _yaw, 0.0)
	head.rotation = Vector3(-_pitch, 0.0, 0.0)


func _physics_process(delta: float) -> void:
	if not can_move:
		return
	var wish := Vector3.ZERO
	# Управление то же, что и в машине: газ и руль — они же вперёд и вбок.
	# Заводить вторую раскладку под ходьбу незачем, клавиши те же самые.
	wish.z -= Input.get_action_strength(&"throttle")
	wish.z += Input.get_action_strength(&"brake")
	wish.x -= Input.get_action_strength(&"steer_left")
	wish.x += Input.get_action_strength(&"steer_right")
	wish = (global_transform.basis * wish).limit_length(1.0)

	var running := Input.is_action_pressed(&"sprint")
	var target_speed := RUN_SPEED if running else WALK_SPEED
	target_speed *= _ground_drag()

	var planar := Vector3(velocity.x, 0.0, velocity.z)
	if wish.length_squared() > 0.001:
		planar = planar.move_toward(wish * target_speed, ACCELERATION * delta)
	else:
		planar = planar.move_toward(Vector3.ZERO, FRICTION * delta)
	velocity.x = planar.x
	velocity.z = planar.z

	if is_on_floor():
		if Input.is_action_just_pressed(&"jump"):
			velocity.y = JUMP_SPEED
		else:
			velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= 9.81 * delta

	move_and_slide()
	_footsteps(planar.length(), delta)


## Рыхлый песок держит ногу так же, как колесо: идти по нему медленнее.
## Коэффициент берётся из того же справочника покрытий, что и физика колёс, —
## отдельного числа для пешехода нет и быть не должно.
func _ground_drag() -> float:
	var surface := World.surface_at(global_position)
	if surface == null:
		return 1.0
	return lerpf(1.0, 1.0 - SAND_DRAG, surface.softness())


func _footsteps(speed: float, delta: float) -> void:
	if speed < 0.4 or not is_on_floor():
		return
	_step_distance += speed * delta
	# Шаг примерно в семьдесят сантиметров; на бегу он длиннее.
	var stride := 0.72 if speed < WALK_SPEED * 1.2 else 1.05
	if _step_distance < stride:
		return
	_step_distance = 0.0
	var surface := World.surface_at(global_position)
	var id: StringName = surface.id if surface != null else &"sand"
	if not _footstep_cache.has(id):
		_footstep_cache[id] = _build_step(id)
	_footstep.stream = _footstep_cache[id]
	_footstep.pitch_scale = randf_range(0.92, 1.09)
	_footstep.play()


## Шаг: короткий шумовой удар, окрашенный грунтом. По камню — щелчок с
## призвуком, по песку — глухой шорох без высоких.
func _build_step(surface_id: StringName) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = Rng.hash_string("step:%s" % surface_id)
	var frames := int(0.17 * float(Synth.RATE))
	var raw := PackedFloat32Array()
	raw.resize(frames)
	var decay := 34.0
	match surface_id:
		&"rock", &"gravel":
			decay = 52.0
		&"track", &"asphalt":
			decay = 42.0
		&"sand_soft", &"sand_firm":
			decay = 22.0
	for i: int in frames:
		var t := float(i) / float(Synth.RATE)
		raw[i] = Synth.white(rng) * exp(-t * decay)
	var shaped := raw
	match surface_id:
		&"rock", &"gravel":
			shaped = Synth.band_pass(raw, 2100.0, 0.9)
		&"sand_soft", &"sand_firm":
			shaped = Synth.low_pass(raw, 900.0)
		_:
			shaped = Synth.low_pass(raw, 1500.0)
	return Synth.to_stream(Synth.normalise(shaped, 0.45), false)
