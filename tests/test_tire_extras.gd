extends TestCase
## Стабилизирующий момент, выцветание тормозов и плотность воздуха. Три
## механизма, которые в игре не показываются цифрой, но каждый меняет то, как
## машина едет.


## Знак — единственное, что здесь важно, и единственное, что легко перепутать.
##
## Проверять надо против увода, а не против боковой силы: сила сама уводу
## противоположна, и «момент против силы» означает «момент по уводу», то есть
## ровно наоборот. Со знаком минус машина не держит прямую и поворачивает не в
## ту сторону, куда просят рулём.
func test_aligning_moment_opposes_the_slip_not_the_force() -> void:
	# Увод вправо: шина отвечает силой влево (отрицательной), и момент обязан
	# быть отрицательным вместе с ней — он возвращает колесо на курс.
	var lateral := TireModel.forces(0.0, 0.05, 20000.0, 1.0, 0.12, 0.14).y
	check(lateral < 0.0, "сила противоположна уводу")
	var moment := TireModel.aligning_moment(0.05, lateral, 0.22)
	check(moment < 0.0, "и момент вместе с ней, а не против неё")

	var mirrored := TireModel.aligning_moment(
		-0.05, TireModel.forces(0.0, -0.05, 20000.0, 1.0, 0.12, 0.14).y, 0.22
	)
	check(mirrored > 0.0, "на другую сторону — зеркально")
	check_near(absf(moment), absf(mirrored), 1.0, "борта симметричны")


## След схлопывается раньше, чем кончается сцепление: руль «пустеет» до срыва.
## Это единственное предупреждение, которое машина даёт до потери передней оси.
func test_the_trail_collapses_before_the_grip_does() -> void:
	var small := absf(TireModel.aligning_moment(0.03, -3000.0, 0.22))
	var large := absf(TireModel.aligning_moment(0.16, -3000.0, 0.22))
	check(large < small, "на большом уводе момент меньше: %.1f против %.1f" % [large, small])
	check_equal(TireModel.aligning_moment(0.30, -3000.0, 0.22), 0.0, "за пределом следа нет")


## Плечо момента — это плечо, а не расчётная длина пятна. На спущенном колесе
## под нагрузкой модель пятна выдаёт до трёх четвертей метра; принять это за
## плечо значит получить момент в разы больше настоящего.
func test_the_trail_has_a_physical_ceiling() -> void:
	var uncapped := 20000.0 * 0.75 * TireModel.TRAIL_RATIO
	var actual := absf(TireModel.aligning_moment(0.02, -20000.0, 0.75))
	check(actual < uncapped, "потолок сработал: %.0f вместо %.0f Н·м" % [actual, uncapped])
	check(actual <= 20000.0 * TireModel.TRAIL_MAX + 1.0, "момент в пределах потолка")
	# Короткое пятно потолка не касается и считается как есть.
	var short := absf(TireModel.aligning_moment(0.02, -20000.0, 0.28))
	check_near(
		short,
		20000.0 * 0.28 * TireModel.TRAIL_RATIO * (1.0 - 0.02 / 0.20),
		1.0,
		"короткое пятно считается без потолка"
	)


func test_brakes_work_until_they_get_hot() -> void:
	check_equal(TireModel.brake_fade(120.0), 1.0, "холодные тормоза в полную силу")
	check_equal(TireModel.brake_fade(TireModel.BRAKE_FADE_START), 1.0, "до порога потерь нет")
	var warm := TireModel.brake_fade(450.0)
	var hot := TireModel.brake_fade(TireModel.BRAKE_FADE_FULL)
	check_between(warm, 0.4, 0.95, "на четырёхстах пятидесяти тормоза слабее")
	check(hot < warm, "дальше хуже")
	check(hot >= 0.3, "совсем без тормозов не остаётся: это всё-таки не отказ")


## Ради чего всё: в жару машина едет хуже. Атмосферный мотор теряет ровно ту
## долю, на которую разрежён воздух, и в пустыне это не третий знак.
func test_hot_air_costs_power() -> void:
	var cool := TireModel.air_density(15.0)
	var noon := TireModel.air_density(45.0)
	check_near(cool, TireModel.AIR_DENSITY_NOMINAL, 0.01, "пятнадцать градусов — норма")
	check(noon < cool, "горячий воздух реже")
	var loss := 1.0 - noon / cool
	check_between(loss, 0.07, 0.12, "потеря около десятой части: %.3f" % loss)


func test_altitude_costs_power_too() -> void:
	var sea := TireModel.air_density(30.0, 0.0)
	var high := TireModel.air_density(30.0, 900.0)
	check(high < sea, "наверху воздух реже")
	check_between(1.0 - high / sea, 0.05, 0.16, "девятьсот метров — около десятой части")
