extends Node
## Прогон всех тестов из res://tests. Запуск:
##   godot --headless --path . res://tests/run_tests.tscn
##
## Сцена, а не `--script`, потому что тестам нужны автолоады, а они появляются
## только в обычном главном цикле.

const TEST_DIR := "res://tests"

var _passed: int = 0
var _failed: int = 0
var _checks: int = 0
var _filter: String = ""


func _ready() -> void:
	_filter = _argument("--filter")
	print_rich("[b]Khamsin — тесты[/b] (Godot %s)" % Engine.get_version_info()["string"])
	var files := _discover()
	if files.is_empty():
		push_error("Тесты не найдены в %s" % TEST_DIR)
		get_tree().quit(1)
		return
	for path: String in files:
		await _run_file(path)
	_report()


func _argument(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with(name + "="):
			return args[i].substr(name.length() + 1)
	return ""


func _discover() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return out
	for file_name: String in dir.get_files():
		if file_name == "test_case.gd":
			continue
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			out.append(TEST_DIR.path_join(file_name))
	out.sort()
	return out


func _run_file(path: String) -> void:
	var script: GDScript = load(path)
	if script == null:
		_failed += 1
		print_rich("[color=red]  не загрузился %s[/color]" % path)
		return
	var instance: Object = script.new()
	if instance == null:
		# Файл с ошибкой разбора грузится, но не создаётся. Раньше это уходило
		# в тишину: тест просто не выполнялся, а набор оставался зелёным.
		_failed += 1
		print_rich("[color=red]  ✗ %s не собрался: смотрите ошибки разбора выше[/color]" % path)
		return
	if not instance is TestCase:
		_failed += 1
		print_rich("[color=red]  ✗ %s не наследует TestCase[/color]" % path)
		return
	var case := instance as TestCase
	case.host = self
	var suite := path.get_file().trim_suffix(".gd")
	print_rich("[b]%s[/b]" % suite)

	for method: Dictionary in script.get_script_method_list():
		var name: String = method["name"]
		if not name.begins_with("test_"):
			continue
		if _filter != "" and not (suite + "." + name).contains(_filter):
			continue
		case.failures = PackedStringArray()
		var before := case.checks
		# Что висело на раннере до теста. Всё, что появится сверху, — его
		# хозяйство, и убрать его надо гарантированно.
		var kept := get_children()
		case.before_each()
		var result: Variant = case.call(name)
		# Тест с await — корутина. Godot возвращает для неё не Signal, а объект
		# GDScriptFunctionState с сигналом completed. Раннер раньше проверял
		# только `result is Signal`, не находил его и шёл дальше, не дождавшись
		# теста: асинхронные тесты молча не выполнялись и всё равно считались
		# пройденными. Проверяем оба вида.
		if result is Signal:
			await result
		elif result is Object and result != null and (result as Object).has_signal("completed"):
			await (result as Object).completed
		case.after_each()
		await _scrub(kept)
		_checks += case.checks - before
		if case.failures.is_empty():
			_passed += 1
			print_rich("  [color=green]✓[/color] %s" % name)
		else:
			_failed += 1
			print_rich("  [color=red]✗[/color] %s" % name)
			for failure: String in case.failures:
				print_rich("      [color=red]%s[/color]" % failure)


## Уборка после теста.
##
## Тесты убирают за собой через queue_free, а он срабатывает в конце кадра.
## Этого мало: следующий тест успевает поставить свою машину ровно туда, где
## ещё стоит коллизия предыдущего, и получает не чистый стенд, а столкновение
## двух грузовиков. Выглядит это необъяснимо — подвеска не несёт вес, машина
## висит в четырёх метрах над землёй и не падает.
##
## Поэтому сцена приводится к исходному виду принудительно: всё, что тест
## добавил на раннер, снимается с дерева. Снятие с дерева, в отличие от
## queue_free, убирает коллизию из физического мира сразу.
func _scrub(kept: Array[Node]) -> void:
	# Открытый экран ставит дерево на паузу — и у следующего теста машина
	# просто не падает: физика не идёт. Найти это по симптому невозможно,
	# выглядит как «подвеска не работает». Закрываем всё и снимаем паузу.
	SceneRouter.close_all()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Дальше выходим из физического кадра: менять дерево во время обхода
	# запросов физики нельзя.
	await get_tree().process_frame
	for child: Node in get_children():
		if kept.has(child):
			continue
		remove_child(child)
		child.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame


func _report() -> void:
	print("")
	if _failed == 0:
		print_rich(
			"[color=green][b]Всё зелёное[/b][/color]: %d тестов, %d проверок" % [_passed, _checks]
		)
	else:
		print_rich(
			"[color=red][b]Провалено %d[/b][/color] из %d, проверок %d"
			% [_failed, _passed + _failed, _checks]
		)
	get_tree().quit(0 if _failed == 0 else 1)
