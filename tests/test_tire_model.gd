extends TestCase
## Шина: форма кривой, знаки сил, эллипс трения, поведение в песке.
##
## Это те свойства, из-за нарушения которых машина едет боком или разгоняется
## назад, а по коду не видно ничего подозрительного.

const LOAD := 10000.0
const MU := 0.9
const KAPPA_PEAK := 0.14
const ALPHA_PEAK := 0.14


func test_curve_peaks_at_normalised_one() -> void:
	var peak := TireModel.curve(1.0)
	check_near(peak, 1.0, 0.02, "максимум кривой должен приходиться на s = 1")
	check(TireModel.curve(0.5) < peak, "до пика кривая должна быть ниже")
	check(TireModel.curve(3.0) < peak, "после пика кривая должна падать")
	check_near(TireModel.curve(0.0), 0.0, 1e-6, "без скольжения нет силы")


func test_curve_falls_to_realistic_plateau() -> void:
	# Полная блокировка колеса — примерно семь пиковых проскальзываний.
	var locked := TireModel.curve(7.0)
	check_between(locked, 0.72, 0.88, "на юзе должно оставаться около 0.8 от пика")


func test_longitudinal_sign() -> void:
	# Колесо крутится быстрее дороги — шина толкает машину вперёд.
	var forces := TireModel.forces(0.14, 0.0, LOAD, MU, KAPPA_PEAK, ALPHA_PEAK)
	check_greater(forces.x, 0.0, "положительное проскальзывание должно толкать вперёд")
	check_near(forces.y, 0.0, 1.0, "без увода нет боковой силы")
	var braking := TireModel.forces(-0.14, 0.0, LOAD, MU, KAPPA_PEAK, ALPHA_PEAK)
	check(braking.x < 0.0, "отрицательное проскальзывание должно тормозить")


func test_lateral_force_opposes_slip() -> void:
	# Машину сносит вправо — шина должна тянуть влево.
	var forces := TireModel.forces(0.0, 0.14, LOAD, MU, KAPPA_PEAK, ALPHA_PEAK)
	check(forces.y < 0.0, "боковая сила должна быть направлена против сноса")
	var mirrored := TireModel.forces(0.0, -0.14, LOAD, MU, KAPPA_PEAK, ALPHA_PEAK)
	check_near(mirrored.y, -forces.y, 1.0, "шина должна быть симметричной")


func test_friction_ellipse_never_exceeds_grip() -> void:
	var limit := MU * LOAD * 1.001
	for i: int in 21:
		for j: int in 21:
			var kappa := lerpf(-1.0, 1.0, float(i) / 20.0)
			var alpha := lerpf(-0.7, 0.7, float(j) / 20.0)
			var f := TireModel.forces(kappa, alpha, LOAD, MU, KAPPA_PEAK, ALPHA_PEAK)
			if f.length() > limit:
				fail("суммарная сила %.1f превысила предел сцепления %.1f при k=%.2f a=%.2f"
					% [f.length(), limit, kappa, alpha])
				return
	check(true, "эллипс трения выдержан во всём диапазоне")


func test_combined_slip_steals_from_both_channels() -> void:
	var pure := TireModel.forces(0.14, 0.0, LOAD, MU, KAPPA_PEAK, ALPHA_PEAK)
	var combined := TireModel.forces(0.14, 0.14, LOAD, MU, KAPPA_PEAK, ALPHA_PEAK)
	check(
		combined.x < pure.x,
		"газ в повороте должен отбирать продольную силу: %.0f против %.0f" % [combined.x, pure.x]
	)


func test_load_sensitivity_reduces_grip() -> void:
	var light := TireModel.effective_mu(1.0, 1.0, 5000.0, 10000.0, 0.25, 0.0)
	var heavy := TireModel.effective_mu(1.0, 1.0, 15000.0, 10000.0, 0.25, 0.0)
	check(heavy < light, "перегруженная шина должна цепляться хуже в пересчёте на ньютон")
	check_near(
		TireModel.effective_mu(1.0, 1.0, 10000.0, 10000.0, 0.25, 0.0),
		1.0,
		0.001,
		"на номинальной нагрузке поправки быть не должно"
	)


func test_wear_costs_more_on_grippy_surfaces() -> void:
	var worn_asphalt := TireModel.effective_mu(1.0, 1.0, 10000.0, 10000.0, 0.0, 1.0)
	var worn_sand := TireModel.effective_mu(1.0, 0.5, 10000.0, 10000.0, 0.0, 1.0)
	check_near(worn_asphalt, 0.65, 0.01, "лысая резина на асфальте теряет треть")
	check_greater(worn_sand / 0.5, 0.8, "на песке износ должен значить меньше")


func test_deflating_tires_grows_contact_patch() -> void:
	var hard := TireModel.patch_length(10000.0, 2.4, 0.32, 0.5)
	var soft := TireModel.patch_length(10000.0, 1.0, 0.32, 0.5)
	check_greater(soft, hard, "спущенное колесо должно давать длиннее пятно")
	check_between(hard, 0.08, 0.20, "пятно накачанного колеса под тонной нагрузки, метры")
	check_between(soft / hard, 1.6, 2.4, "с 2.4 до 1.0 бар пятно должно вырасти примерно вдвое")


func test_deflection_softens_with_pressure() -> void:
	var hard := TireModel.deflection(10000.0, 2.4, 2.4, 0.5)
	var soft := TireModel.deflection(10000.0, 1.0, 2.4, 0.5)
	check_between(hard, 0.015, 0.05, "прогиб накачанной шины, метры")
	check_greater(soft, hard * 1.4, "спущенная шина должна проседать заметно сильнее")


func test_lower_pressure_reduces_sinkage_in_sand() -> void:
	var sand := Surface.get_by_id(&"sand_soft")
	var width := 0.32
	var hard_area := TireModel.patch_area(10000.0, 2.4, width, 0.5)
	var soft_area := TireModel.patch_area(10000.0, 1.0, width, 0.5)
	var hard_sink := TireModel.sinkage(sand, 10000.0, hard_area)
	var soft_sink := TireModel.sinkage(sand, 10000.0, soft_area)
	check_greater(hard_sink, soft_sink, "накачанное колесо должно закапываться глубже")
	var hard_drag := TireModel.motion_resistance(sand, 10000.0, hard_sink, 2.4)
	var soft_drag := TireModel.motion_resistance(sand, 10000.0, soft_sink, 1.0)
	check_greater(
		hard_drag, soft_drag,
		"сопротивление на накачанных колёсах должно быть выше: %.0f против %.0f" % [hard_drag, soft_drag]
	)
	check_greater(hard_drag / soft_drag, 1.9, "выигрыш от спуска колёс должен быть ощутимым")
	# Проверяем и абсолютный порядок: на накачанных колёсах в дюне машина почти
	# не едет, на спущенных — едет тяжело, но едет.
	check_between(hard_drag / 10000.0, 0.20, 0.34, "доля веса, уходящая в сопротивление, на 2.4 бар")
	check_between(soft_drag / 10000.0, 0.07, 0.17, "то же на 1.0 бар")


func test_deflating_hurts_on_hard_ground() -> void:
	# Обратная сторона: на асфальте спущенные колёса только мешают.
	var asphalt := Surface.get_by_id(&"asphalt")
	var hard := TireModel.motion_resistance(asphalt, 10000.0, 0.0, 2.4)
	var soft := TireModel.motion_resistance(asphalt, 10000.0, 0.0, 1.0)
	check_greater(soft, hard * 1.5, "на твёрдом покрытии спущенная шина должна катиться тяжелее")


func test_surfaces_are_ordered_by_difficulty() -> void:
	var asphalt := Surface.get_by_id(&"asphalt")
	var track := Surface.get_by_id(&"track")
	var firm := Surface.get_by_id(&"sand_firm")
	var soft := Surface.get_by_id(&"sand_soft")
	check(asphalt.grip > track.grip, "асфальт должен держать лучше накатки")
	check(track.grip > firm.grip, "накатка должна держать лучше плотного песка")
	check(firm.grip > soft.grip, "плотный песок должен держать лучше рыхлого")
	check(soft.bulldoze > firm.bulldoze, "рыхлый песок должен сгребаться тяжелее")
	check(
		TireModel.surface_hardness(asphalt) > TireModel.surface_hardness(soft),
		"асфальт должен считаться твёрдым, песок — нет"
	)
	check(Surface.get_by_id(&"нет такого").id == &"gravel", "неизвестное покрытие должно давать хамаду")


func test_relaxation_converges_and_survives_standstill() -> void:
	var value := 0.0
	for _i: int in 200:
		value = TireModel.relax(value, 0.2, 20.0, 0.4, 1.0 / 120.0)
	check_near(value, 0.2, 0.005, "на скорости фильтр должен сходиться к цели")

	var parked := 0.5
	for _i: int in 600:
		parked = TireModel.relax(parked, 0.0, 0.0, 0.4, 1.0 / 120.0)
	check_near(parked, 0.0, 0.01, "на стоящей машине скольжение должно затухать, а не залипать")
