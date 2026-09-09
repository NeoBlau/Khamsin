extends Node
## Переключение экранов и пауза.
##
## Верхний уровень (меню ↔ игра) меняется через `change_scene_to_file`. Всё
## остальное — карта, биржа, гараж, диалог, пауза — накладывается поверх мира
## слоем этого автолоада, чтобы мир не выгружался и машина не теряла состояние.

signal screen_opened(screen: StringName)
signal screen_closed(screen: StringName)

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/game.tscn"

const SCREENS: Dictionary[StringName, String] = {
	&"map": "res://scenes/ui/map_screen.tscn",
	&"contracts": "res://scenes/ui/settlement_screen.tscn",
	&"garage": "res://scenes/ui/settlement_screen.tscn",
	&"dialogue": "res://scenes/ui/dialogue_screen.tscn",
	&"pause": "res://scenes/ui/pause_menu.tscn",
	&"settings": "res://scenes/ui/settings_screen.tscn",
	&"journal": "res://scenes/ui/journal_screen.tscn",
}

var _overlay_layer: CanvasLayer
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _stack: Array[StringName] = []
var _transitioning: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "Overlays"
	_overlay_layer.layer = 50
	add_child(_overlay_layer)

	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "Fade"
	_fade_layer.layer = 100
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.043, 0.039, 0.055, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.visible = false
	_fade_layer.add_child(_fade_rect)

	EventBus.screen_requested.connect(_on_screen_requested)


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning:
		return
	if event.is_action_pressed(&"pause"):
		if _stack.is_empty():
			if GameState.is_running:
				open(&"pause")
		else:
			close_top()
		get_viewport().set_input_as_handled()


func current_screen() -> StringName:
	return _stack.back() if not _stack.is_empty() else &""


func is_overlay_open() -> bool:
	return not _stack.is_empty()


func _on_screen_requested(screen: StringName, payload: Dictionary) -> void:
	open(screen, payload)


func open(screen: StringName, payload: Dictionary = {}) -> void:
	if not SCREENS.has(screen):
		push_error("SceneRouter: нет экрана '%s'" % screen)
		return
	if _stack.has(screen):
		return
	var path: String = SCREENS[screen]
	if not ResourceLoader.exists(path):
		push_error("SceneRouter: сцена '%s' не найдена" % path)
		return
	var packed: PackedScene = load(path)
	var node := packed.instantiate()
	node.name = String(screen)
	if screen == &"garage":
		payload = payload.duplicate()
		payload["tab"] = 3
	if node.has_method(&"setup"):
		node.call(&"setup", payload)
	_overlay_layer.add_child(node)
	_stack.append(screen)
	_refresh_pause()
	screen_opened.emit(screen)


func close(screen: StringName) -> void:
	var index := _stack.find(screen)
	if index == -1:
		return
	_stack.remove_at(index)
	var node := _overlay_layer.get_node_or_null(NodePath(String(screen)))
	if node != null:
		node.queue_free()
	_refresh_pause()
	screen_closed.emit(screen)


func close_top() -> void:
	if _stack.is_empty():
		return
	close(_stack.back())


func close_all() -> void:
	for screen: StringName in _stack.duplicate():
		close(screen)


## Мир замирает, пока открыт любой оверлей, кроме карты: по карте удобно
## смотреть маршрут на ходу, и это осознанная поблажка, а не забытый случай.
func _refresh_pause() -> void:
	var should_pause := false
	for screen: StringName in _stack:
		if screen != &"map":
			should_pause = true
	get_tree().paused = should_pause


func goto_menu() -> void:
	close_all()
	GameState.is_running = false
	await _fade(1.0, 0.25)
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)
	await get_tree().process_frame
	await _fade(0.0, 0.35)


func start_new_game(world_seed: int, difficulty: StringName = &"normal") -> void:
	close_all()
	await _fade(1.0, 0.3)
	GameState.new_game(world_seed, difficulty)
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)
	await get_tree().process_frame
	await _fade(0.0, 0.5)


func load_game(slot: int) -> bool:
	close_all()
	await _fade(1.0, 0.3)
	if not SaveSystem.load_from_slot(slot):
		EventBus.notify("Не загрузить сейв: %s" % SaveSystem.last_error(), &"error")
		await _fade(0.0, 0.3)
		return false
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)
	await get_tree().process_frame
	await _fade(0.0, 0.5)
	return true


func _fade(target_alpha: float, duration: float) -> void:
	_transitioning = true
	_fade_rect.visible = true
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", target_alpha, duration)
	await tween.finished
	_fade_rect.visible = target_alpha > 0.01
	_transitioning = false
