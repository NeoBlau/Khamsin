extends Node
## Разовые замеры. Не тест — инструмент: печатает числа, по которым настраивают
## машину. Содержимое меняется под текущий вопрос.

const STEP := 1.0 / 120.0


func _ready() -> void:
	Catalog.ensure_loaded()
	GameState.new_game(1)

	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000.0, 6.0, 24000.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0.0, -3.0, 0.0)
	var material := PhysicsMaterial.new()
	material.friction = 1.0
	ground.physics_material_override = material
	add_child(ground)

	var truck := VehicleBody.new()
	truck.config_id = &"tabuk_6t"
	truck.player_controlled = false
	truck.surface_provider = func(_p: Vector3) -> Surface: return Surface.get_by_id(&"asphalt")
	add_child(truck)
	truck.global_position = Vector3(0.0, 1.4, 0.0)
	truck.set_pressure_all(2.2)
	for _i: int in 300:
		await get_tree().physics_frame

	print("t  |v|  v_прод об/мин пер  силы по колёсам (Н)                 сумма  сопр  аэро")
	truck.input.throttle = 1.0
	var elapsed := 0.0
	var next_print := 0.0
	while elapsed < 40.0:
		await get_tree().physics_frame
		elapsed += STEP
		if elapsed >= next_print:
			next_print += 5.0
			var wheel := truck.wheels[2]
			var total := 0.0
			var parts := PackedStringArray()
			for w: VehicleWheel in truck.wheels:
				var longitudinal := w.force_longitudinal - signf(w.contact_speed_long) * w.resistance
				total += longitudinal
				parts.append("%7.0f" % longitudinal)
			var speed := truck.linear_velocity.length()
			var drag := 0.5 * Config.air_density * speed * speed * truck.config.drag_coefficient \
				* truck.config.frontal_area
			print("%4.1f %5.1f %6.1f %6.0f %3d  %s %7.0f %6.0f %5.0f"
				% [
					elapsed, speed * 3.6, truck.forward_speed * 3.6, truck.drivetrain.rpm(),
					truck.drivetrain.gear, " ".join(parts), total,
					truck.wheels[0].resistance * 4.0, drag,
				])
	get_tree().quit()
