extends TestCase
## Самый дешёвый и самый полезный тест: каждый скрипт проекта должен грузиться.
##
## `--check-only` в консоли этого не ловит, потому что там нет автолоадов, и
## любое обращение к `Config` или `EventBus` выглядит ошибкой. Здесь дерево уже
## поднято, поэтому ошибка компиляции — настоящая ошибка.

const ROOTS: PackedStringArray = ["res://src", "res://tests", "res://tools"]


func test_every_script_loads() -> void:
	var files := _collect()
	check_greater(float(files.size()), 10.0, "скриптов должно быть заметно больше десятка")
	for path: String in files:
		var script: Variant = load(path)
		if not check(script != null, "не загрузился %s" % path):
			continue
		# `load` возвращает объект и для скрипта с ошибкой разбора: у сломанного
		# просто нет валидного класса, и создать экземпляр он не может.
		check((script as GDScript).can_instantiate(), "не компилируется %s" % path)


func _collect(dirs: PackedStringArray = ROOTS) -> PackedStringArray:
	var out := PackedStringArray()
	var pending := Array(dirs)
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		for sub: String in dir.get_directories():
			pending.append(current.path_join(sub))
		for file_name: String in dir.get_files():
			if file_name.ends_with(".gd"):
				out.append(current.path_join(file_name))
	out.sort()
	return out
