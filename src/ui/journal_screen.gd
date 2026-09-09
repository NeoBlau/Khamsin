extends Screen
## Журнал: где мы в сюжете, что везём, с кем в каких отношениях.

func window_title() -> String:
	return "Журнал"


func window_size() -> Vector2:
	return Vector2(760.0, 560.0)


func build_body() -> void:
	var director: StoryDirector = null
	var nodes := get_tree().get_nodes_in_group(&"story_director")
	if not nodes.is_empty():
		director = nodes[0]

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)

	if director != null:
		column.add_child(Widgets.label(director.chapter_title(), 19, UiTheme.SAND))
		column.add_child(Widgets.wrapped(director.objective(), 15, UiTheme.INK))
		column.add_child(Widgets.separator())

	column.add_child(Widgets.label("Груз в кузове", 16, UiTheme.SAND))
	var contracts := GameState.active_contracts()
	if contracts.is_empty():
		column.add_child(Widgets.label("Пусто.", 14, UiTheme.INK_FAINT))
	else:
		var now := GameState.total_hours()
		for contract: Contract in contracts:
			var destination := World.settlement(contract.destination_id)
			column.add_child(
				Widgets.field(
					"%s ×%d → %s" % [
						contract.cargo().display_name, contract.units, destination.display_name
					],
					"%d%% · %.1f ч" % [roundi(contract.integrity * 100.0), contract.hours_left(now)],
					UiTheme.gauge_colour(contract.integrity)
				)
			)
	column.add_child(Widgets.separator())

	column.add_child(Widgets.label("Отношения", 16, UiTheme.SAND))
	for faction: StringName in GameState.reputation.keys():
		var value := GameState.reputation_of(faction)
		column.add_child(
			Widgets.field(_faction_name(faction), "%+.0f · %s" % [value, _standing(value)])
		)
	column.add_child(Widgets.separator())

	column.add_child(Widgets.label("Итоги", 16, UiTheme.SAND))
	column.add_child(Widgets.field("Пройдено", Settings.format_distance(
		float(GameState.stats.get("distance_driven", 0.0))
	)))
	column.add_child(Widgets.field("Сожжено топлива", "%.0f л" % float(GameState.stats.get("fuel_burned", 0.0))))
	column.add_child(Widgets.field("Доставлено", str(GameState.stats.get("deliveries", 0))))
	column.add_child(Widgets.field("Провалено", str(GameState.stats.get("failures", 0))))
	column.add_child(Widgets.field("Переворотов", str(GameState.stats.get("rollovers", 0))))
	body.add_child(Widgets.scroll(column))


func _faction_name(faction: StringName) -> String:
	match faction:
		&"guild": return "Гильдия перевозчиков"
		&"nomads": return "Кочевые семьи"
		&"company": return "Компания"
	return String(faction)


func _standing(value: float) -> String:
	if value >= 40.0:
		return "свой"
	if value >= 15.0:
		return "доверяют"
	if value > -10.0:
		return "нейтрально"
	if value > -40.0:
		return "косо смотрят"
	return "враждебно"
