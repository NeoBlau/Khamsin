extends CanvasLayer
## Приборы и подсказки поверх мира.
##
## Правило компоновки: слева то, что говорит о машине, справа — о дороге,
## сверху — о времени и задаче. В центре не висит ничего, кроме предупреждений,
## потому что центр экрана — это то место, куда игрок смотрит, когда едет.
##
## Обновляется не каждый кадр целиком: цифры приборов — да, а списки и подписи
## — раз в пятую долю секунды. Разница незаметна глазу и заметна профайлеру.

const SLOW_INTERVAL := 0.2
const TOAST_LIFETIME := 4.5

var vehicle: VehicleBody
var weather: Weather
var story: StoryDirector

var _speed: Label
var _speed_unit: Label
var _gear: Label
var _rpm: ProgressBar
var _rpm_fill: StyleBoxFlat
var _drive_mode: Label
var _fuel: ProgressBar
var _fuel_fill: StyleBoxFlat
var _fuel_text: Label
var _temperature: Label
var _pressure: Label
var _cargo: VBoxContainer
var _clock: Label
var _weather_line: Label
var _objective: Label
var _compass: CompassStrip
var _minimap: Minimap
var _toasts: VBoxContainer
var _warnings: VBoxContainer
var _slow_timer: float = 0.0
var _warning_state: Dictionary[StringName, bool] = {}


func setup(target: VehicleBody, sky_weather: Weather, director: StoryDirector) -> void:
	vehicle = target
	weather = sky_weather
	story = director


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.theme()
	add_child(root)

	_build_top(root)
	_build_left(root)
	_build_right(root)
	_build_centre(root)

	EventBus.notification_posted.connect(_on_notification)
	EventBus.vehicle_warning.connect(_on_warning)
	EventBus.vehicle_stuck_changed.connect(_on_stuck)


# --- Сборка ----------------------------------------------------------------

func _build_top(root: Control) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	box.position = Vector2(18.0, 14.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_clock = Widgets.label("", 20, UiTheme.INK)
	_weather_line = Widgets.label("", 13, UiTheme.INK_DIM)
	_objective = Widgets.label("", 13, UiTheme.SAND)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size = Vector2(360.0, 0.0)
	box.add_child(_clock)
	box.add_child(_weather_line)
	box.add_child(_objective)
	root.add_child(box)

	_compass = CompassStrip.new()
	_compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_compass.position = Vector2(-230.0, 26.0)
	root.add_child(_compass)


func _build_left(root: Control) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(18.0, -132.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)

	_speed = Widgets.label("0", 54, UiTheme.INK)
	_speed_unit = Widgets.label("км/ч", 13, UiTheme.INK_DIM)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	speed_row.add_child(_speed)
	var unit_box := VBoxContainer.new()
	unit_box.add_child(Widgets.spacer(30.0))
	unit_box.add_child(_speed_unit)
	speed_row.add_child(unit_box)
	box.add_child(speed_row)

	_rpm = ProgressBar.new()
	_rpm.custom_minimum_size = Vector2(210.0, 5.0)
	_rpm.show_percentage = false
	_rpm.max_value = 1.0
	var rpm_background := StyleBoxFlat.new()
	rpm_background.bg_color = Color(0.16, 0.15, 0.14, 0.85)
	_rpm_fill = StyleBoxFlat.new()
	_rpm_fill.bg_color = UiTheme.SAND
	_rpm.add_theme_stylebox_override("background", rpm_background)
	_rpm.add_theme_stylebox_override("fill", _rpm_fill)
	box.add_child(_rpm)

	_gear = Widgets.label("N", 17, UiTheme.INK)
	_drive_mode = Widgets.label("", 12, UiTheme.INK_DIM)
	box.add_child(Widgets.row([_gear, _drive_mode], 12))
	root.add_child(box)


func _build_right(root: Control) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.position = Vector2(-262.0, -250.0)
	box.custom_minimum_size = Vector2(244.0, 0.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)

	_minimap = Minimap.new()
	box.add_child(_minimap)

	_fuel = ProgressBar.new()
	_fuel.custom_minimum_size = Vector2(244.0, 6.0)
	_fuel.show_percentage = false
	_fuel.max_value = 1.0
	var fuel_background := StyleBoxFlat.new()
	fuel_background.bg_color = Color(0.16, 0.15, 0.14, 0.85)
	_fuel_fill = StyleBoxFlat.new()
	_fuel_fill.bg_color = UiTheme.GOOD
	_fuel.add_theme_stylebox_override("background", fuel_background)
	_fuel.add_theme_stylebox_override("fill", _fuel_fill)
	_fuel_text = Widgets.label("", 12, UiTheme.INK_DIM)
	box.add_child(_fuel_text)
	box.add_child(_fuel)

	_temperature = Widgets.label("", 12, UiTheme.INK_DIM)
	_pressure = Widgets.label("", 12, UiTheme.INK_DIM)
	box.add_child(_temperature)
	box.add_child(_pressure)

	_cargo = VBoxContainer.new()
	_cargo.add_theme_constant_override("separation", 2)
	box.add_child(_cargo)
	root.add_child(box)


func _build_centre(root: Control) -> void:
	_warnings = VBoxContainer.new()
	_warnings.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_warnings.position = Vector2(-160.0, 92.0)
	_warnings.custom_minimum_size = Vector2(320.0, 0.0)
	_warnings.alignment = BoxContainer.ALIGNMENT_CENTER
	_warnings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_warnings)

	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toasts.position = Vector2(-210.0, -190.0)
	_toasts.custom_minimum_size = Vector2(420.0, 0.0)
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)


# --- Обновление ------------------------------------------------------------

func _process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	_update_fast()
	_slow_timer += delta
	if _slow_timer >= SLOW_INTERVAL:
		_slow_timer = 0.0
		_update_slow()


func _update_fast() -> void:
	var speed := absf(vehicle.forward_speed)
	_speed.text = str(roundi(speed * (2.2369363 if Settings.units == Settings.Units.IMPERIAL else 3.6)))
	_speed_unit.text = "mph" if Settings.units == Settings.Units.IMPERIAL else "км/ч"

	var drivetrain := vehicle.drivetrain
	var fraction := clampf(drivetrain.rpm() / maxf(drivetrain.config.max_rpm, 1.0), 0.0, 1.0)
	_rpm.value = fraction
	var redline := drivetrain.config.redline_rpm / maxf(drivetrain.config.max_rpm, 1.0)
	_rpm_fill.bg_color = UiTheme.DANGER if fraction > redline else UiTheme.SAND

	_gear.text = _gear_name(drivetrain.gear)


func _gear_name(gear: int) -> String:
	if gear < 0:
		return "R"
	if gear == 0:
		return "N"
	return str(gear)


func _update_slow() -> void:
	_clock.text = "День %d   %02d:%02d" % [
		GameState.day, floori(GameState.time_of_day), roundi(fposmod(GameState.time_of_day, 1.0) * 60.0)
	]
	if weather != null:
		_weather_line.text = weather.forecast_line()
	if story != null:
		_objective.text = story.objective()

	var drivetrain := vehicle.drivetrain
	var mode := PackedStringArray()
	mode.append("4x4" if drivetrain.awd else "4x2")
	if drivetrain.low_range:
		mode.append("пониж.")
	if drivetrain.diff_locked:
		mode.append("блок.")
	_drive_mode.text = "  ".join(mode)

	var fuel_fraction := vehicle.fuel / maxf(vehicle.config.fuel_capacity, 1.0)
	_fuel.value = fuel_fraction
	_fuel_fill.bg_color = UiTheme.gauge_colour(fuel_fraction)
	# Запас хода честнее процентов: он и решает, дотянешь ли до заправки.
	_fuel_text.text = "Топливо %.0f л   запас %s" % [vehicle.fuel, _range_estimate()]

	var temperature := drivetrain.coolant_temp
	_temperature.text = "Двигатель %.0f °C%s" % [
		temperature, "   перегрев" if temperature > 104.0 else ""
	]
	_temperature.add_theme_color_override(
		"font_color", UiTheme.DANGER if temperature > 104.0 else UiTheme.INK_DIM
	)
	_pressure.text = "Шины %.1f бар   износ %d%%" % [
		vehicle.wheels[0].pressure, roundi(_worst_tire_wear() * 100.0)
	]

	_update_cargo()
	_update_navigation()
	_update_warnings()


## Запас хода по фактическому расходу за последние минуты, а не по паспортному.
func _range_estimate() -> String:
	var rate := vehicle.drivetrain.fuel_rate
	var speed := absf(vehicle.forward_speed) * 3.6
	if rate < 0.5 or speed < 3.0:
		return "—"
	var hours := vehicle.fuel / rate
	return Settings.format_distance(hours * speed * 1000.0)


func _worst_tire_wear() -> float:
	var worst := 0.0
	for wheel: VehicleWheel in vehicle.wheels:
		worst = maxf(worst, wheel.wear)
	return worst


func _update_cargo() -> void:
	for child: Node in _cargo.get_children():
		child.queue_free()
	var contracts := GameState.active_contracts()
	if contracts.is_empty():
		_cargo.add_child(Widgets.label("Кузов пуст", 12, UiTheme.INK_FAINT))
		return
	var now := GameState.total_hours()
	for contract: Contract in contracts:
		var cargo := contract.cargo()
		if cargo == null:
			continue
		var left := contract.hours_left(now)
		var deadline := "просрочен" if left < 0.0 else "%.1f ч" % left
		var colour := UiTheme.gauge_colour(contract.integrity)
		if left < 0.0:
			colour = UiTheme.DANGER
		_cargo.add_child(
			Widgets.field(
				"%s ×%d" % [cargo.display_name, contract.units],
				"%d%%   %s" % [roundi(contract.integrity * 100.0), deadline],
				colour
			)
		)


func _update_navigation() -> void:
	var heading := rad_to_deg(atan2(-vehicle.global_transform.basis.z.x, -vehicle.global_transform.basis.z.z))
	heading = fposmod(180.0 - heading, 360.0)

	var waypoint := _waypoint()
	var markers: Array[Dictionary] = []
	if waypoint != null:
		var delta := waypoint.position - Vector2(vehicle.global_position.x, vehicle.global_position.z)
		var bearing := fposmod(rad_to_deg(atan2(delta.x, -delta.y)), 360.0)
		markers.append({
			"bearing": bearing,
			"colour": UiTheme.SAND,
			"label": "%s  %s" % [waypoint.display_name, Settings.format_distance(delta.length())],
		})
	_compass.set_state(heading, markers)
	_minimap.set_state(vehicle.global_position, heading, waypoint)


## Куда ехать: адрес ближайшего по сроку заказа, иначе ближайший известный
## посёлок. Отдельного выбора цели в интерфейсе нет намеренно — в пустыне
## курьер едет туда, где его ждут.
func _waypoint() -> Settlement:
	var best: Contract = null
	for contract: Contract in GameState.active_contracts():
		if best == null or contract.deadline_hours < best.deadline_hours:
			best = contract
	if best != null:
		return World.settlement(best.destination_id)
	return World.nearest_settlement(vehicle.global_position)


func _update_warnings() -> void:
	_set_warning(&"fuel", vehicle.fuel < vehicle.config.fuel_capacity * 0.1, "Топливо на исходе")
	_set_warning(&"heat", vehicle.drivetrain.coolant_temp > 108.0, "Двигатель перегревается")
	_set_warning(&"stall", not vehicle.drivetrain.running, "Двигатель заглох — газ, чтобы завести")
	_set_warning(&"stuck", vehicle.is_stuck, "Колёса буксуют. Спустите шины или включите блокировки")
	_set_warning(&"roll", vehicle.rolled_over, "Машина на боку. R — эвакуатор")


func _set_warning(id: StringName, active: bool, text: String) -> void:
	if _warning_state.get(id, false) == active:
		return
	_warning_state[id] = active
	var name := "warn_%s" % id
	var existing := _warnings.get_node_or_null(NodePath(name))
	if not active:
		if existing != null:
			existing.queue_free()
		return
	if existing != null:
		return
	var label := Widgets.label(text, 15, UiTheme.WARNING)
	label.name = name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warnings.add_child(label)
	EventBus.vehicle_warning.emit(id, true)


# --- Сообщения -------------------------------------------------------------

func _on_notification(text: String, kind: StringName) -> void:
	var colour := UiTheme.INK
	match kind:
		&"warning":
			colour = UiTheme.WARNING
		&"error":
			colour = UiTheme.DANGER
		&"good":
			colour = UiTheme.GOOD
	var label := Widgets.label(text, 15, colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toasts.add_child(label)
	# Больше четырёх сообщений подряд читать некогда — старые уходят сразу.
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))
	var tween := create_tween()
	tween.tween_interval(TOAST_LIFETIME)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func _on_warning(_kind: StringName, _active: bool) -> void:
	pass


func _on_stuck(stuck: bool) -> void:
	if stuck:
		EventBus.notify("Закопались. Спустите шины до 1.0 бар и включите блокировки", &"warning")
