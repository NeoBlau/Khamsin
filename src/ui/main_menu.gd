extends Control
## Главное меню.
##
## Сид мира виден и вводится руками: это не отладка, а часть игры. Одинаковый
## сид — одинаковая пустыня, и обмениваться удачными мирами так же естественно,
## как названиями мест.

var _seed_field: LineEdit
var _slots: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()

	var background := ColorRect.new()
	background.color = Color(0.055, 0.05, 0.055)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var frame := VBoxContainer.new()
	frame.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	frame.position = Vector2(88.0, -180.0)
	frame.custom_minimum_size = Vector2(420.0, 0.0)
	frame.add_theme_constant_override("separation", 10)
	add_child(frame)

	frame.add_child(Widgets.label("ХАМСИН", 52, UiTheme.SAND))
	frame.add_child(Widgets.label("курьерский рейс через эрг", 15, UiTheme.INK_DIM))
	frame.add_child(Widgets.spacer(18.0))

	_seed_field = LineEdit.new()
	_seed_field.text = str(Rng.world_seed)
	_seed_field.custom_minimum_size = Vector2(200.0, 0.0)
	frame.add_child(Widgets.row([Widgets.label("Сид мира", 14, UiTheme.INK_DIM), _seed_field], 12))

	frame.add_child(Widgets.button("Новый рейс", _new_game))
	if SaveSystem.slot_exists(SaveSystem.AUTOSAVE_SLOT) or SaveSystem.slot_exists(1):
		frame.add_child(Widgets.button("Продолжить", _continue))
	frame.add_child(Widgets.button("Настройки", func() -> void:
		EventBus.screen_requested.emit(&"settings", {})
	))
	frame.add_child(Widgets.button("Выход", func() -> void: get_tree().quit()))

	frame.add_child(Widgets.spacer(16.0))
	frame.add_child(Widgets.label("Сохранения", 15, UiTheme.SAND))
	_slots = VBoxContainer.new()
	_slots.add_theme_constant_override("separation", 4)
	frame.add_child(_slots)
	_refresh_slots()

	var hint := Widgets.wrapped(
		"WASD — газ, тормоз, руль. Пробел — ручник. F — полный привод, G — блокировки,"
		+ " T — пониженная. Скобки — давление в шинах. M — карта, J — журнал,"
		+ " C — камера, R — эвакуатор.",
		13, UiTheme.INK_FAINT
	)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.position = Vector2(88.0, -70.0)
	hint.custom_minimum_size = Vector2(620.0, 0.0)
	add_child(hint)


func _refresh_slots() -> void:
	for child: Node in _slots.get_children():
		child.queue_free()
		_slots.remove_child(child)
	var any := false
	for slot: int in SaveSystem.SLOT_COUNT:
		var summary := SaveSystem.slot_summary(slot)
		if summary.is_empty():
			continue
		any = true
		var title := "Автосохранение" if slot == SaveSystem.AUTOSAVE_SLOT else "Слот %d" % slot
		var description := "День %d · %s · %s" % [
			int(summary.get("day", 1)),
			Settings.format_money(float(summary.get("money", 0.0))),
			Settings.format_distance(float(summary.get("odometer", 0.0))),
		]
		var button := Widgets.button("%s — %s" % [title, description], _load_slot.bind(slot))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_slots.add_child(button)
	if not any:
		_slots.add_child(Widgets.label("Пока пусто.", 13, UiTheme.INK_FAINT))


func _new_game() -> void:
	var text := _seed_field.text.strip_edges()
	var world_seed := int(text) if text.is_valid_int() else Rng.hash_string(text)
	if text.is_empty():
		world_seed = randi()
	SceneRouter.start_new_game(world_seed)


func _continue() -> void:
	var slot := 1 if SaveSystem.slot_exists(1) else SaveSystem.AUTOSAVE_SLOT
	SceneRouter.load_game(slot)


func _load_slot(slot: int) -> void:
	SceneRouter.load_game(slot)
