extends Control
## Заставка при запуске.
##
## Показывается ровно один раз за сеанс и уходит по любой клавише или сама
## через несколько секунд. Заставка, которую нельзя пропустить, — это налог,
## который игрок платит каждый запуск; здесь его нет.

const HOLD := 4.2
const FADE := 0.7

var _art: CoverArt
var _prompt: Label
var _veil: ColorRect
var _age: float = 0.0
var _leaving: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()

	_art = CoverArt.new()
	_art.seed_value = Rng.world_seed
	_art.show_title = true
	add_child(_art)

	_prompt = Widgets.label("нажмите любую клавишу", 15, Color(0.86, 0.78, 0.60))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-160.0, -90.0)
	_prompt.custom_minimum_size = Vector2(320.0, 0.0)
	add_child(_prompt)

	_veil = ColorRect.new()
	_veil.color = Color(0.03, 0.03, 0.04, 1.0)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)

	set_process(true)
	set_process_unhandled_input(true)


func _process(delta: float) -> void:
	_age += delta
	if not _leaving:
		# Появление из черноты, потом мигание подсказки.
		_veil.color.a = clampf(1.0 - _age / FADE, 0.0, 1.0)
		_prompt.modulate.a = 0.35 + 0.35 * (1.0 + sin(_age * 2.4)) * 0.5
		if _age > HOLD:
			leave()
		return
	_veil.color.a = clampf(_veil.color.a + delta / FADE, 0.0, 1.0)
	if _veil.color.a >= 1.0:
		get_tree().change_scene_to_file(SceneRouter.MENU_SCENE)
		set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or _age < 0.35:
		return
	if event is InputEventKey and event.pressed:
		leave()
	elif event is InputEventMouseButton and event.pressed:
		leave()
	elif event is InputEventJoypadButton and event.pressed:
		leave()


func leave() -> void:
	if _leaving:
		return
	_leaving = true
	_prompt.visible = false
