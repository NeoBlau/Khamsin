extends Node
## Прогон всех тестов из res://tests. Запуск:
##   godot --headless --path games/khamsin res://tests/run_tests.tscn
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
	if not instance is TestCase:
		print_rich("[color=yellow]  пропущен %s: не наследует TestCase[/color]" % path)
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
		case.before_each()
		var result: Variant = case.call(name)
		# Тест-корутина возвращает сигнал своего завершения — его и ждём.
		if result is Signal:
			await result
		case.after_each()
		_checks += case.checks - before
		if case.failures.is_empty():
			_passed += 1
			print_rich("  [color=green]✓[/color] %s" % name)
		else:
			_failed += 1
			print_rich("  [color=red]✗[/color] %s" % name)
			for failure: String in case.failures:
				print_rich("      [color=red]%s[/color]" % failure)


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
