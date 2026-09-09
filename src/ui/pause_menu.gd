extends Screen
## Пауза: сохраниться, настроить, выйти.

func window_title() -> String:
	return "Пауза"


func window_size() -> Vector2:
	return Vector2(460.0, 420.0)


func build_body() -> void:
	body.add_child(Widgets.field("День", "%d, %02d:%02d" % [
		GameState.day, floori(GameState.time_of_day), roundi(fposmod(GameState.time_of_day, 1.0) * 60.0)
	]))
	body.add_child(Widgets.field("Наличные", Settings.format_money(GameState.money)))
	body.add_child(Widgets.separator())

	body.add_child(Widgets.button("Продолжить", close))
	body.add_child(Widgets.button("Сохранить", _save))
	body.add_child(Widgets.button("Настройки", _open_settings))
	body.add_child(Widgets.spacer(12.0))
	body.add_child(Widgets.button("В главное меню", _to_menu))
	body.add_child(Widgets.button("Выйти из игры", _quit))
	body.add_child(Widgets.spacer())
	body.add_child(Widgets.caption("Автосохранение работает каждые несколько минут."))


func _save() -> void:
	var vehicles := get_tree().get_nodes_in_group(&"player_vehicle")
	if not vehicles.is_empty():
		(vehicles[0] as VehicleBody).sync_to_state()
	if SaveSystem.save_to_slot(1):
		EventBus.notify("Сохранено в слот 1", &"good")
	else:
		EventBus.notify("Не сохранить: %s" % SaveSystem.last_error(), &"error")


func _open_settings() -> void:
	EventBus.screen_requested.emit(&"settings", {})


func _to_menu() -> void:
	_save()
	SceneRouter.goto_menu()


func _quit() -> void:
	_save()
	get_tree().quit()
