extends TestCase
## Шейдеры хотя бы разбираются.
##
## Полноценно собрать их без видеокарты нельзя, но разбор кода идёт при
## загрузке ресурса, и по списку униформ видно, дошёл ли парсер до конца. Это
## ловит ровно тот класс ошибок, который иначе обнаруживается только глазами:
## сломанный шейдер в Godot не краснеет, а просто перестаёт рисовать.

const EXPECTED: Dictionary[String, Array] = {
	"res://shaders/terrain.gdshader": [
		"sand_colour", "rock_colour", "track_colour", "wind_direction", "debug_view",
	],
	"res://shaders/sky.gdshader": ["zenith_day", "horizon_day", "dust", "day_factor"],
}


func test_shaders_parse_and_expose_their_uniforms() -> void:
	for path: String in EXPECTED.keys():
		var shader: Shader = load(path)
		if not check(shader != null, "шейдер %s должен грузиться" % path):
			continue
		var names := PackedStringArray()
		for entry: Dictionary in shader.get_shader_uniform_list():
			names.append(String(entry["name"]))
		check_greater(float(names.size()), 3.0, "%s: разбор должен дойти до униформ" % path)
		for expected: String in EXPECTED[path]:
			check(names.has(expected), "%s: нет униформы '%s'" % [path, expected])


func test_fragment_has_no_early_return() -> void:
	# В шейдерах Godot `return` внутри fragment запрещён, а сообщение об этом
	# приходит только на живой видеокарте. Ловим на уровне текста.
	for path: String in EXPECTED.keys():
		var code := FileAccess.get_file_as_string(path)
		var start := code.find("void fragment()")
		if start == -1:
			continue
		var tail := _strip_comments(code.substr(start))
		check(
			not tail.contains("return"),
			"%s: в fragment не должно быть return — шейдер молча перестанет рисоваться" % path
		)


## Убирает построчные комментарии: слово «return» в объяснении, почему его
## нельзя писать, не должно валить проверку.
func _strip_comments(code: String) -> String:
	var out := PackedStringArray()
	for line: String in code.split("\n"):
		var index := line.find("//")
		out.append(line.substr(0, index) if index != -1 else line)
	return "\n".join(out)
