class_name WheelDust
extends GPUParticles3D
## Пыль из-под колеса.
##
## Не украшение: по шлейфу видно, буксует колесо или катится, и на каком грунте
## оно стоит. На камне пыли почти нет, в рыхлом песке она стоит стеной — это
## первый признак того, что пора спускать колёса.

const MAX_RATE := 90.0

var wheel: VehicleWheel

var _material: ParticleProcessMaterial


func _ready() -> void:
	amount = 96
	lifetime = 1.6
	explosiveness = 0.0
	local_coords = false
	draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	emitting = false

	_material = ParticleProcessMaterial.new()
	_material.direction = Vector3(0.0, 0.35, 1.0)
	_material.spread = 28.0
	_material.initial_velocity_min = 1.0
	_material.initial_velocity_max = 4.5
	_material.gravity = Vector3(0.0, -1.1, 0.0)
	_material.damping_min = 1.4
	_material.damping_max = 2.6
	_material.scale_min = 0.5
	_material.scale_max = 1.5
	# Пыль не тает, а оседает и светлеет: облако за машиной висит долго и
	# постепенно растворяется в общей дымке.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 2.0))
	var scale_curve := CurveTexture.new()
	scale_curve.curve = curve
	_material.scale_curve = scale_curve

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.90, 0.81, 0.62, 0.42))
	gradient.set_color(1, Color(0.84, 0.75, 0.56, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	_material.color_ramp = ramp
	process_material = _material

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.75, 0.75)
	var surface := StandardMaterial3D.new()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	surface.vertex_color_use_as_albedo = true
	surface.albedo_color = Color(0.86, 0.77, 0.58)
	surface.disable_receive_shadows = true
	# Без мягкой маски частица остаётся квадратом: за машиной летят не клубы
	# пыли, а картонные коробки. Радиальный градиент дешевле любой текстуры и
	# не требует ни одного файла.
	surface.albedo_texture = _soft_blob()
	mesh.material = surface
	draw_pass_1 = mesh


## Круглое мягкое пятно вместо текстуры.
static func _soft_blob() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.55), Color(1.0, 1.0, 1.0, 0.0)
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


## Обновляется вместе с колесом: интенсивность считается из проскальзывания,
## скорости и пыльности грунта.
func update(delta: float) -> void:
	if wheel == null or not wheel.grounded:
		emitting = false
		return
	global_position = wheel.contact_point + Vector3.UP * 0.12

	var rolling := absf(wheel.contact_speed_long)
	var slipping := absf(wheel.slip_ratio * maxf(rolling, 1.0)) + absf(wheel.contact_speed_lat)
	var intensity := clampf((rolling * 0.35 + slipping * 0.8) / 14.0, 0.0, 1.0)
	intensity *= wheel.surface.dust
	emitting = intensity > 0.03
	if not emitting:
		return
	amount_ratio = clampf(intensity, 0.05, 1.0)
	_material.initial_velocity_max = lerpf(2.0, 7.0, intensity)
	# Пыль летит назад относительно движения колеса, а не по фиксированной оси.
	var direction := -global_transform.basis.z
	if rolling > 0.5:
		direction = Vector3.FORWARD
	_material.direction = Vector3(0.0, 0.45, 1.0)
