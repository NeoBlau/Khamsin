extends TestCase
## Выход из машины и возвращение за руль.
##
## Тут почти всё — состояние, которое легко рассинхронизировать: камера,
## захват мыши, ручник, управляемость. Ошибка в любом из них выглядит как
## «игра зависла»: персонаж не двигается, машина не едет, мышь пропала.

var game: Node3D


func before_each() -> void:
	Catalog.ensure_loaded()
	GameState.new_game(20260907)


func after_each() -> void:
	if game != null and is_instance_valid(game):
		game.queue_free()
	game = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _start() -> Node3D:
	game = load("res://scenes/game.tscn").instantiate()
	host.add_child(game)
	await game.world_ready
	# Машина появляется над землёй и оседает на подвеске. Пока она падает,
	# выходить из неё и правда нельзя, так что даём ей встать.
	await simulate(1.6)
	game.vehicle.linear_velocity = Vector3.ZERO
	game.vehicle.angular_velocity = Vector3.ZERO
	await simulate(0.2)
	return game


func test_leaving_and_boarding_round_trip() -> void:
	await _start()
	check(not game.on_foot, "начинаем за рулём")
	check(game.vehicle.player_controlled, "машина слушается игрока")

	check(game.leave_vehicle(), "вышли из машины")
	check(game.on_foot, "теперь пешком")
	check(not game.vehicle.player_controlled, "машина больше не слушается руля")
	check(game.walker.can_move, "персонаж может идти")
	check(game.walker.camera.current, "смотрим глазами персонажа")
	check(not game.camera.current, "камера машины уступила")

	check(game.board_vehicle(), "сели обратно")
	check(not game.on_foot, "снова за рулём")
	check(game.vehicle.player_controlled, "машина опять слушается")
	check(game.camera.current, "камера машины вернулась")
	check(not game.walker.can_move, "персонаж замер")


## Выпрыгивать на ходу нельзя. Это не строгость ради строгости: иначе игрок
## выходит на пятидесяти, машина уезжает сама, и догнать её невозможно.
func test_cannot_step_out_while_moving() -> void:
	await _start()
	game.vehicle.linear_velocity = Vector3(9.0, 0.0, 0.0)
	check(not game.leave_vehicle(), "на ходу выйти нельзя")
	check(not game.on_foot, "остались за рулём")
	# Вертикальная скорость выходу не мешает: машина, осевшая на подвеске,
	# стоит на месте.
	game.vehicle.linear_velocity = Vector3(0.1, -2.5, 0.0)
	check(game.leave_vehicle(), "просевшая на подвеске — можно")


## Дверь не телепорт: до машины надо дойти.
func test_cannot_board_from_across_the_desert() -> void:
	await _start()
	check(game.leave_vehicle(), "вышли")
	var far: Vector3 = game.vehicle.global_position + Vector3(40.0, 0.0, 0.0)
	game.walker.global_position = Vector3(far.x, World.height(far.x, far.z) + 0.2, far.z)
	check(not game.board_vehicle(), "с сорока метров сесть нельзя")
	check(game.on_foot, "всё ещё пешком")
	game.walker.global_position = game.vehicle.global_position + Vector3(1.5, 0.0, 0.0)
	check(game.board_vehicle(), "вплотную — можно")


## Выходить надо у двери, а не в кузов, не под машину и не в песок под ней.
func test_player_steps_out_beside_the_door() -> void:
	await _start()
	var vehicle_at: Vector3 = game.vehicle.global_position
	check(game.leave_vehicle(), "вышли")
	var spot: Vector3 = game.walker.global_position
	var sideways: float = absf(game.vehicle.to_local(spot).x)
	var size: Vector3 = game.vehicle.config.body_size
	check(sideways > size.x * 0.5, "встали сбоку от машины, а не внутри неё: %.2f м" % sideways)
	check(spot.distance_to(vehicle_at) < 6.0, "но рядом, а не за горизонтом")
	var ground := World.height(spot.x, spot.z)
	check(spot.y > ground - 0.5, "ноги на земле, а не под ней")
	check(spot.y < ground + 2.5, "и не в воздухе")


## Ручник при выходе обязателен: иначе машина, оставленная на склоне дюны,
## уезжает сама, пока игрок стоит рядом.
func test_handbrake_is_set_when_leaving() -> void:
	await _start()
	game.vehicle.input.handbrake = 0.0
	check(game.leave_vehicle(), "вышли")
	check(game.vehicle.input.handbrake > 0.5, "ручник затянут")
	check(game.board_vehicle(), "сели")
	check(game.vehicle.input.handbrake < 0.5, "и отпущен обратно")


func test_walking_actually_moves_the_player() -> void:
	await _start()
	check(game.leave_vehicle(), "вышли")
	var began: Vector3 = game.walker.global_position
	# Идём вперёд руками, без ввода: проверяем контроллер, а не клавиатуру.
	for _i: int in 90:
		game.walker.velocity.x = 2.0
		game.walker.move_and_slide()
		await tree().physics_frame
	var moved: float = began.distance_to(game.walker.global_position)
	check(moved > 1.0, "персонаж прошёл %.2f м" % moved)
	check(game.walker.global_position.y > World.height(
		game.walker.global_position.x, game.walker.global_position.z) - 1.0,
		"и не провалился сквозь землю")


## Рыхлый песок держит ногу так же, как колесо. Число берётся из того же
## справочника покрытий — своего у пешехода нет.
func test_soft_sand_slows_walking() -> void:
	var firm := Surface.get_by_id(&"rock")
	var soft := Surface.get_by_id(&"sand_soft")
	check(firm.softness() < soft.softness(), "камень твёрже рыхлого песка")
	check_near(firm.softness(), 0.0, 0.001, "по камню идётся без потерь")
	check(soft.softness() > 0.9, "рыхлый песок вязнет почти полностью")
