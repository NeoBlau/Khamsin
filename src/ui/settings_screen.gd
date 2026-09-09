extends Screen
## Настройки. Меняются сразу и сразу сохраняются на диск: отдельная кнопка
## «применить» нужна там, где изменения дорогие, а здесь они бесплатные.

func window_title() -> String:
	return "Настройки"


func window_size() -> Vector2:
	return Vector2(720.0, 600.0)


func build_body() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)

	column.add_child(Widgets.label("Управление", 16, UiTheme.SAND))
	column.add_child(_choice(
		"Коробка передач", ["Автомат", "Ручная"], Settings.transmission,
		func(index: int) -> void: Settings.set_option(&"input", &"transmission", index)
	))
	column.add_child(_toggle("Антиблокировка (ABS)", Settings.assist_abs, &"assist_abs", &"input"))
	column.add_child(_toggle("Противобуксовочная", Settings.assist_traction, &"assist_traction", &"input"))
	column.add_child(_toggle("Стабилизация", Settings.assist_stability, &"assist_stability", &"input"))
	column.add_child(_slider("Чувствительность руля", Settings.steer_sensitivity, 0.4, 1.6, &"steer_sensitivity", &"input"))
	column.add_child(_slider("Мёртвая зона стика", Settings.gamepad_deadzone, 0.05, 0.4, &"gamepad_deadzone", &"input"))
	column.add_child(Widgets.separator())

	column.add_child(Widgets.label("Изображение", 16, UiTheme.SAND))
	column.add_child(_slider("Масштаб отрисовки", Settings.render_scale, 0.5, 1.5, &"render_scale", &"graphics"))
	column.add_child(_slider("Поле зрения", Settings.fov, 55.0, 100.0, &"fov", &"graphics"))
	column.add_child(_choice(
		"Тени", ["Выкл", "Низкие", "Средние", "Высокие"], Settings.shadow_quality,
		func(index: int) -> void: Settings.set_option(&"graphics", &"shadow_quality", index)
	))
	column.add_child(_toggle("Вертикальная синхронизация", Settings.vsync, &"vsync", &"graphics"))
	column.add_child(Widgets.separator())

	column.add_child(Widgets.label("Звук", 16, UiTheme.SAND))
	column.add_child(_slider("Общая громкость", Settings.volume_master, 0.0, 1.0, &"volume_master", &"audio"))
	column.add_child(_slider("Двигатель", Settings.volume_engine, 0.0, 1.0, &"volume_engine", &"audio"))
	column.add_child(_slider("Мир", Settings.volume_world, 0.0, 1.0, &"volume_world", &"audio"))
	column.add_child(Widgets.separator())

	column.add_child(Widgets.label("Игра", 16, UiTheme.SAND))
	column.add_child(_choice(
		"Единицы", ["Метрические", "Мили"], Settings.units,
		func(index: int) -> void: Settings.set_option(&"game", &"units", index)
	))
	column.add_child(_slider("Автосохранение, мин", Settings.autosave_minutes, 0.0, 20.0, &"autosave_minutes"))
	body.add_child(Widgets.scroll(column))


func _toggle(title: String, value: bool, key: StringName, section: StringName = &"game") -> Control:
	var button := CheckBox.new()
	button.button_pressed = value
	button.toggled.connect(func(pressed: bool) -> void:
		Settings.set_option(section, key, pressed)
	)
	var label := Widgets.label(title, 14, UiTheme.INK_DIM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return Widgets.row([label, button])


func _slider(
	title: String, value: float, low: float, high: float, key: StringName,
	section: StringName = &"game"
) -> Control:
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = (high - low) / 40.0
	slider.value = value
	slider.custom_minimum_size = Vector2(260.0, 0.0)
	var readout := Widgets.label(_format(value), 13, UiTheme.INK)
	readout.custom_minimum_size = Vector2(56.0, 0.0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(new_value: float) -> void:
		readout.text = _format(new_value)
		Settings.set_option(section, key, new_value)
	)
	var label := Widgets.label(title, 14, UiTheme.INK_DIM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return Widgets.row([label, slider, readout])


func _format(value: float) -> String:
	return "%.2f" % value if value < 10.0 else "%.0f" % value


func _choice(title: String, options: Array, selected: int, on_change: Callable) -> Control:
	var button := OptionButton.new()
	for i: int in options.size():
		button.add_item(String(options[i]), i)
	button.select(clampi(selected, 0, options.size() - 1))
	button.item_selected.connect(on_change)
	var label := Widgets.label(title, 14, UiTheme.INK_DIM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return Widgets.row([label, button])
