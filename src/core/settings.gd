extends Node
## Пользовательские настройки: графика, звук, управление, помощники.
##
## Живут в `user://settings.cfg`, не в сейве — они про машину игрока, а не про
## прохождение. Применяются сразу при изменении: подписываться на `changed` и
## перечитывать нужное поле.

signal changed(section: StringName, key: StringName, value: Variant)

const PATH := "user://settings.cfg"
const BUSES: Array[StringName] = [&"Engine", &"World", &"UI"]

enum Units { METRIC, IMPERIAL }
enum Transmission { AUTOMATIC, MANUAL }

# --- Графика ---------------------------------------------------------------

var render_scale: float = 1.0
var draw_distance_scale: float = 1.0
var shadow_quality: int = 2  ## 0 выкл, 1 низкое, 2 среднее, 3 высокое
var msaa: int = 1  ## индекс Viewport.MSAA_*
var vsync: bool = true
var fov: float = 72.0
var motion_blur: bool = false

# --- Звук ------------------------------------------------------------------

var volume_master: float = 0.9
var volume_engine: float = 0.85
var volume_world: float = 0.8
var volume_ui: float = 0.7

# --- Управление ------------------------------------------------------------

var steer_sensitivity: float = 1.0
## Скорость, с которой руль возвращается в ноль без ввода, в долях хода за секунду.
var steer_return_rate: float = 2.6
var mouse_sensitivity: float = 0.15
var invert_look_y: bool = false
var gamepad_deadzone: float = 0.16
var force_feedback: bool = true

# --- Игра ------------------------------------------------------------------

var units: int = Units.METRIC
var transmission: int = Transmission.AUTOMATIC
var assist_abs: bool = true
var assist_traction: bool = true
var assist_stability: bool = false
var show_route_line: bool = true
var autosave_minutes: float = 5.0
var language: String = "ru"

var _loaded: bool = false


func _ready() -> void:
	_ensure_buses()
	load_from_disk()
	apply_all()


func _ensure_buses() -> void:
	for bus_name: StringName in BUSES:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, &"Master")


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		_loaded = true
		return
	for section: String in cfg.get_sections():
		for key: String in cfg.get_section_keys(section):
			if key in self:
				set(key, cfg.get_value(section, key))
	_loaded = true


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "draw_distance_scale", draw_distance_scale)
	cfg.set_value("graphics", "shadow_quality", shadow_quality)
	cfg.set_value("graphics", "msaa", msaa)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "fov", fov)
	cfg.set_value("graphics", "motion_blur", motion_blur)
	cfg.set_value("audio", "volume_master", volume_master)
	cfg.set_value("audio", "volume_engine", volume_engine)
	cfg.set_value("audio", "volume_world", volume_world)
	cfg.set_value("audio", "volume_ui", volume_ui)
	cfg.set_value("input", "steer_sensitivity", steer_sensitivity)
	cfg.set_value("input", "steer_return_rate", steer_return_rate)
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("input", "invert_look_y", invert_look_y)
	cfg.set_value("input", "gamepad_deadzone", gamepad_deadzone)
	cfg.set_value("input", "force_feedback", force_feedback)
	cfg.set_value("game", "units", units)
	cfg.set_value("game", "transmission", transmission)
	cfg.set_value("game", "assist_abs", assist_abs)
	cfg.set_value("game", "assist_traction", assist_traction)
	cfg.set_value("game", "assist_stability", assist_stability)
	cfg.set_value("game", "show_route_line", show_route_line)
	cfg.set_value("game", "autosave_minutes", autosave_minutes)
	cfg.set_value("game", "language", language)
	cfg.save(PATH)


## Меняет поле по имени, применяет и сохраняет. Так интерфейсу не нужно знать
## про раскладку файла — только про имя настройки.
func set_option(section: StringName, key: StringName, value: Variant) -> void:
	if not String(key) in self:
		push_warning("Settings: нет опции '%s'" % key)
		return
	set(String(key), value)
	apply_all()
	save_to_disk()
	changed.emit(section, key, value)


func apply_all() -> void:
	_apply_audio()
	_apply_graphics()
	_apply_input()


func _apply_audio() -> void:
	_set_bus_volume(&"Master", volume_master)
	_set_bus_volume(&"Engine", volume_engine)
	_set_bus_volume(&"World", volume_world)
	_set_bus_volume(&"UI", volume_ui)


func _set_bus_volume(bus: StringName, value: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, value <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))


func _apply_graphics() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var vp := tree.root
	vp.scaling_3d_scale = clampf(render_scale, 0.5, 2.0)
	vp.msaa_3d = clampi(msaa, 0, 3)
	var atlas: int = [1024, 2048, 4096, 8192][clampi(shadow_quality, 0, 3)]
	vp.positional_shadow_atlas_size = atlas
	RenderingServer.directional_shadow_atlas_set_size(atlas, shadow_quality >= 2)


func _apply_input() -> void:
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		var current := InputMap.action_get_deadzone(action)
		if current > 0.05 and current < 0.45:
			InputMap.action_set_deadzone(action, gamepad_deadzone)


## Скорость в тех единицах, которые выбрал игрок, плюс подпись.
func format_speed(metres_per_second: float) -> String:
	if units == Units.IMPERIAL:
		return "%d mph" % roundi(metres_per_second * 2.2369363)
	return "%d км/ч" % roundi(metres_per_second * 3.6)


func format_distance(metres: float) -> String:
	if units == Units.IMPERIAL:
		var miles := metres / 1609.344
		return "%.1f mi" % miles if miles < 100.0 else "%d mi" % roundi(miles)
	if metres < 1000.0:
		return "%d м" % roundi(metres)
	return "%.1f км" % (metres / 1000.0)


## Разряды пробелами: 12 400 читается быстрее, чем 12400.
func _group_digits(value: int) -> String:
	var sign_prefix := "-" if value < 0 else ""
	var digits := String.num_int64(absi(value))
	var out := ""
	var count := 0
	for i: int in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return sign_prefix + out


func format_money(amount: float) -> String:
	return "%s дх" % _group_digits(roundi(amount))
