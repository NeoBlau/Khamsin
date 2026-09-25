class_name Camel
extends CharacterBody3D
## Верблюд.
##
## Ведёт себя не как препятствие, а как животное, которому вы мешаете. Пока вы
## далеко — пасётся и бродит. Подъехали близко — поднимает голову и смотрит.
## Подъехали слишком близко или слишком быстро — плюёт. Плевок летит по дуге,
## прилипает к кузову и не смывается ничем, кроме мойки в оазисе Дяди Вали.
##
## Это не шутка ради шутки: плевок портит обзор через стекло и заставляет
## сделать крюк. Механика ровно та же, что с давлением в шинах, — неудобство,
## у которого есть внятное лекарство в конкретной точке карты.

signal spat_at(target: Node3D, from: Vector3)

enum Mood { GRAZING, ALERT, ANNOYED }

const WALK_SPEED := 1.1
const TROT_SPEED := 3.4
const NOTICE_RANGE := 26.0
const SPIT_RANGE := 11.0
## Насколько быстро надо проехать мимо, чтобы верблюд счёл это оскорблением.
const RUDE_SPEED := 7.0
const SPIT_COOLDOWN := 9.0
const HEIGHT := 2.25

var home: Vector3 = Vector3.ZERO
var wander_radius: float = 34.0
var mood: Mood = Mood.GRAZING

var _rng := RandomNumberGenerator.new()
var _target: Vector3 = Vector3.ZERO
var _think_timer: float = 0.0
var _spit_timer: float = 0.0
var _head: Node3D
var _neck: Node3D
var _legs: Array[Node3D] = []
var _gait: float = 0.0
var _voice: AudioStreamPlayer3D
var _annoyance: float = 0.0


func setup(at: Vector3, seed_value: int) -> void:
	home = at
	_rng.seed = seed_value
	global_position = at
	_target = at


func _ready() -> void:
	add_to_group(&"camel")
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.5

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.55
	capsule.height = HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(shape)

	_build_body()

	_voice = AudioStreamPlayer3D.new()
	_voice.bus = &"World"
	_voice.max_distance = 60.0
	add_child(_voice)

	_think_timer = _rng.randf_range(0.0, 3.0)
	set_physics_process(true)


## Верблюд из примитивов: тело, горб, шея, голова и четыре ноги. Горб и
## длинная шея — весь силуэт: без них это просто лошадь, а с ними узнаётся
## мгновенно даже боковым зрением.
func _build_body() -> void:
	var hide_colour := Color(0.62, 0.50, 0.34)
	var dark := hide_colour.darkened(0.22)

	var body := MeshFactory.panel(Vector3(0.78, 0.86, 1.72), hide_colour, 0.95, 0.0, 0.16)
	body.position = Vector3(0.0, 1.52, 0.0)
	add_child(body)

	var hump := MeshFactory.panel(Vector3(0.62, 0.52, 0.78), hide_colour.lightened(0.05), 0.95, 0.0, 0.22)
	hump.position = Vector3(0.0, 2.08, -0.05)
	add_child(hump)

	_neck = Node3D.new()
	_neck.name = "Neck"
	_neck.position = Vector3(0.0, 1.80, -0.80)
	add_child(_neck)
	var neck_mesh := MeshFactory.panel(Vector3(0.34, 1.05, 0.34), hide_colour, 0.95, 0.0, 0.10)
	neck_mesh.position = Vector3(0.0, 0.42, -0.18)
	neck_mesh.rotation = Vector3(deg_to_rad(22.0), 0.0, 0.0)
	_neck.add_child(neck_mesh)

	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, 0.92, -0.52)
	_neck.add_child(_head)
	var skull := MeshFactory.panel(Vector3(0.28, 0.30, 0.56), hide_colour, 0.9, 0.0, 0.08)
	skull.position = Vector3(0.0, 0.0, -0.16)
	_head.add_child(skull)
	var muzzle := MeshFactory.panel(Vector3(0.20, 0.18, 0.26), dark, 0.9, 0.0, 0.06)
	muzzle.position = Vector3(0.0, -0.06, -0.48)
	_head.add_child(muzzle)
	for side: int in 2:
		var ear := MeshFactory.panel(Vector3(0.06, 0.12, 0.05), dark, 0.9, 0.0, 0.02)
		ear.position = Vector3((0.10 if side == 0 else -0.10), 0.18, 0.02)
		_head.add_child(ear)

	var tail := MeshFactory.panel(Vector3(0.08, 0.44, 0.08), dark, 0.95, 0.0, 0.03)
	tail.position = Vector3(0.0, 1.36, 0.92)
	add_child(tail)

	for i: int in 4:
		var front := i < 2
		var leg := Node3D.new()
		leg.name = "Leg%d" % i
		leg.position = Vector3(
			0.30 if i % 2 == 0 else -0.30, 1.12, -0.58 if front else 0.62
		)
		add_child(leg)
		var upper := MeshFactory.panel(Vector3(0.18, 0.62, 0.18), hide_colour, 0.95, 0.0, 0.05)
		upper.position = Vector3(0.0, -0.31, 0.0)
		leg.add_child(upper)
		var lower := MeshFactory.panel(Vector3(0.13, 0.54, 0.13), dark, 0.95, 0.0, 0.04)
		lower.position = Vector3(0.0, -0.86, 0.0)
		leg.add_child(lower)
		var foot := MeshFactory.panel(Vector3(0.24, 0.10, 0.28), dark.darkened(0.15), 0.95, 0.0, 0.04)
		foot.position = Vector3(0.0, -1.16, 0.02)
		leg.add_child(foot)
		_legs.append(leg)


func _physics_process(delta: float) -> void:
	var driver := _nearest_intruder()
	_update_mood(driver, delta)

	_think_timer -= delta
	if _think_timer <= 0.0:
		_choose_destination(driver)
		_think_timer = _rng.randf_range(2.5, 7.0)

	var speed := WALK_SPEED
	if mood == Mood.ANNOYED:
		speed = TROT_SPEED
	elif mood == Mood.ALERT:
		speed = WALK_SPEED * 0.4

	var to_target := _target - global_position
	to_target.y = 0.0
	if to_target.length() > 1.0:
		var direction := to_target.normalized()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		# Разворот телом: верблюд не стрейфится.
		var wanted := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, wanted, clampf(delta * 2.2, 0.0, 1.0))
	else:
		velocity.x = move_toward(velocity.x, 0.0, delta * 6.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 6.0)

	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= 9.81 * delta
	move_and_slide()

	_animate(delta, Vector2(velocity.x, velocity.z).length())
	_spit_timer = maxf(_spit_timer - delta, 0.0)
	if mood == Mood.ANNOYED and driver != null and _spit_timer <= 0.0:
		if global_position.distance_to(driver.global_position) < SPIT_RANGE:
			_spit_at(driver)


## Ближайшая машина в поле внимания. Пешего игрока верблюд тоже замечает, но
## плюётся именно в машину: шумит и пылит она.
func _nearest_intruder() -> Node3D:
	var best: Node3D = null
	var best_distance := NOTICE_RANGE
	for node: Node in get_tree().get_nodes_in_group(&"player_vehicle"):
		var body := node as Node3D
		if body == null:
			continue
		var distance := global_position.distance_to(body.global_position)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


func _update_mood(driver: Node3D, delta: float) -> void:
	if driver == null:
		_annoyance = maxf(_annoyance - delta * 0.35, 0.0)
		mood = Mood.GRAZING if _annoyance < 0.2 else Mood.ALERT
		return
	var distance := global_position.distance_to(driver.global_position)
	var speed := 0.0
	if driver is VehicleBody:
		speed = absf((driver as VehicleBody).speed)
	# Раздражение копится тем быстрее, чем ближе и быстрее едут мимо.
	var closeness := clampf(1.0 - distance / NOTICE_RANGE, 0.0, 1.0)
	var rudeness := clampf(speed / RUDE_SPEED, 0.0, 2.0)
	_annoyance = clampf(_annoyance + delta * closeness * (0.35 + rudeness * 0.8), 0.0, 2.0)
	if _annoyance > 1.0:
		mood = Mood.ANNOYED
	elif _annoyance > 0.25:
		mood = Mood.ALERT
	else:
		mood = Mood.GRAZING


func _choose_destination(driver: Node3D) -> void:
	if mood == Mood.ANNOYED and driver != null:
		# Раздражённый верблюд не убегает — он идёт разбираться.
		var towards := driver.global_position - global_position
		towards.y = 0.0
		_target = global_position + towards.normalized() * minf(towards.length() * 0.6, 12.0)
		return
	var angle := _rng.randf() * TAU
	var radius := _rng.randf() * wander_radius
	var spot := home + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_target = Vector3(spot.x, World.height(spot.x, spot.z), spot.z)


## Плевок. Летит по дуге, а не по прямой: так его видно и можно увернуться,
## если успеть дать газу.
func _spit_at(target: Node3D) -> void:
	_spit_timer = SPIT_COOLDOWN
	_annoyance = 0.35
	var muzzle := _head.global_position + _head.global_transform.basis.z * -0.5
	var spit := CamelSpit.new()
	spit.launch(muzzle, target, self)
	get_parent().add_child(spit)
	_say(&"spit")
	spat_at.emit(target, muzzle)


func _say(kind: StringName) -> void:
	var profile := Voice.profile(&"camel")
	if kind == &"spit":
		profile.pitch *= 1.35
	var text := "Пфффф." if kind == &"spit" else "Мооо."
	_voice.stream = Synth.to_stream(
		Voice.render_line(text, profile, _rng.randi()), false
	)
	_voice.play()


## Походка: ноги ходят от пройденного пути, а не от таймера. Стоящий верблюд
## не перебирает ногами на месте, и это видно сразу.
func _animate(delta: float, speed: float) -> void:
	_gait += speed * delta * 2.4
	for i: int in _legs.size():
		# Иноходь: верблюд переставляет обе ноги одной стороны вместе. Именно
		# из-за неё всадника укачивает, и именно она узнаётся в силуэте.
		var phase := _gait + (0.0 if i % 2 == 0 else PI)
		_legs[i].rotation.x = sin(phase) * clampf(speed * 0.13, 0.0, 0.42)
	if _neck != null:
		var lift := 0.0
		match mood:
			Mood.GRAZING:
				lift = -0.55 + sin(_gait * 0.3) * 0.08
			Mood.ALERT:
				lift = 0.12
			Mood.ANNOYED:
				lift = 0.28
		_neck.rotation.x = lerp_angle(_neck.rotation.x, lift, clampf(delta * 2.0, 0.0, 1.0))
