class_name TestCase
extends RefCounted
## Минимальный каркас тестов. Внешних зависимостей нет специально: игра должна
## проверяться той же командой, что и собирается, без установки чего-либо.

var failures: PackedStringArray = PackedStringArray()
var checks: int = 0
## Узел раннера. Ставится перед запуском — интеграционным тестам нужно куда-то
## складывать сцену и чем-то ждать кадры физики.
var host: Node = null


func tree() -> SceneTree:
	return host.get_tree() if host != null else null


## Прогоняет N секунд физики. Возвращает фактически пройденное игровое время.
func simulate(seconds: float) -> float:
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	var steps := maxi(1, roundi(seconds / step))
	for _i: int in steps:
		await tree().physics_frame
	return float(steps) * step


## Переопределяется наследником, если тесту нужна подготовка.
func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(message: String) -> void:
	failures.append(message)


func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		fail(message)
	return condition


func check_equal(actual: Variant, expected: Variant, message: String) -> bool:
	return check(actual == expected, "%s: ожидалось %s, получено %s" % [message, expected, actual])


func check_near(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return check(
		absf(actual - expected) <= tolerance,
		"%s: ожидалось %.4f ± %.4f, получено %.4f" % [message, expected, tolerance, actual]
	)


func check_between(actual: float, low: float, high: float, message: String) -> bool:
	return check(
		actual >= low and actual <= high,
		"%s: ожидалось в [%.4f, %.4f], получено %.4f" % [message, low, high, actual]
	)


func check_greater(actual: float, threshold: float, message: String) -> bool:
	return check(actual > threshold, "%s: ожидалось больше %.4f, получено %.4f" % [message, threshold, actual])
