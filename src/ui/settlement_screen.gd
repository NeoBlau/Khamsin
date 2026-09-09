extends Screen
## Посёлок: доска заказов, сдача груза, услуги, гараж.
##
## Один экран с вкладками, а не четыре окна: всё, что игрок делает на стоянке,
## он делает подряд — заправился, починился, сдал, взял новый. Разносить это
## по разным местам значит заставлять его ходить по меню.

enum Tab { BOARD, DELIVER, SERVICES, GARAGE }

var settlement: Settlement
var vehicle: VehicleBody

var _tabs: TabContainer


func window_title() -> String:
	return settlement.display_name if settlement != null else "Посёлок"


func window_size() -> Vector2:
	return Vector2(920.0, 600.0)


func build_body() -> void:
	settlement = World.settlement(StringName(payload.get("settlement", "")))
	if settlement == null:
		settlement = World.nearest_settlement(_vehicle_position())
	vehicle = _find_vehicle()
	set_window_title("%s · %s" % [settlement.display_name, settlement.kind_name()])

	var subtitle := Widgets.wrapped(settlement.description, 13, UiTheme.INK_DIM)
	body.add_child(subtitle)
	body.add_child(_money_line())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(_build_board())
	_tabs.add_child(_build_deliver())
	_tabs.add_child(_build_services())
	_tabs.add_child(_build_garage())
	_tabs.set_tab_title(Tab.BOARD, "Заказы")
	_tabs.set_tab_title(Tab.DELIVER, "Сдать груз")
	_tabs.set_tab_title(Tab.SERVICES, "Услуги")
	_tabs.set_tab_title(Tab.GARAGE, "Гараж")
	_tabs.current_tab = int(payload.get("tab", Tab.BOARD))
	body.add_child(_tabs)


## Пересобирает экран и возвращает игрока на ту же вкладку. После покупки или
## заправки половина цифр меняется, и обновлять их поштучно — верный способ
## что-нибудь забыть.
func _reopen(tab: Tab) -> void:
	rebuild()
	if _tabs != null:
		_tabs.current_tab = int(tab)


func _vehicle_position() -> Vector3:
	var found := _find_vehicle()
	return found.global_position if found != null else Vector3.ZERO


func _find_vehicle() -> VehicleBody:
	var nodes := get_tree().get_nodes_in_group(&"player_vehicle")
	return nodes[0] if not nodes.is_empty() else null


func _money_line() -> Control:
	var config := vehicle.config if vehicle != null else Catalog.vehicle(GameState.vehicle_id)
	return Widgets.row([
		Widgets.label("Наличные: %s" % Settings.format_money(GameState.money), 15, UiTheme.SAND),
		Widgets.label(
			"Кузов: %.0f / %.0f кг · %.1f / %.1f м³"
			% [
				GameState.carried_mass(), config.cargo_mass_limit,
				GameState.carried_volume(), config.cargo_volume_limit
			],
			13, UiTheme.INK_DIM
		),
	], 24)


# --- Доска -----------------------------------------------------------------

func _build_board() -> Control:
	var column := VBoxContainer.new()
	column.name = "Заказы"
	column.add_theme_constant_override("separation", 6)

	var offers := ContractBoard.offers(settlement)
	if offers.is_empty():
		column.add_child(Widgets.label("Сегодня заказов нет. Загляните завтра.", 14, UiTheme.INK_DIM))
		return Widgets.scroll(column)

	for contract: Contract in offers:
		column.add_child(_offer_row(contract))
		column.add_child(Widgets.separator())
	return Widgets.scroll(column)


func _offer_row(contract: Contract) -> Control:
	var cargo := contract.cargo()
	var destination := World.settlement(contract.destination_id)

	var left := Widgets.column([
		Widgets.label("%s ×%d" % [cargo.display_name, contract.units], 16, UiTheme.INK),
		Widgets.label(
			"в %s · %s · %.0f кг"
			% [
				destination.display_name,
				Settings.format_distance(contract.route_length),
				contract.total_mass()
			],
			13, UiTheme.INK_DIM
		),
		Widgets.label(_tags(contract), 12, UiTheme.WARNING),
	], 2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var right := Widgets.column([
		Widgets.label(Settings.format_money(contract.payout), 17, UiTheme.SAND),
		Widgets.label("залог %s" % Settings.format_money(contract.deposit), 12, UiTheme.INK_FAINT),
		Widgets.label("на рейс %.1f ч" % contract.duration_hours, 12, UiTheme.INK_DIM),
	], 2)

	var reason := ContractBoard.rejection_reason(contract, vehicle)
	var do_accept := func() -> void:
		if ContractBoard.accept(contract, vehicle):
			_reopen(Tab.BOARD)
	var take := Widgets.button("Взять", do_accept)
	take.disabled = not reason.is_empty()
	take.tooltip_text = reason
	if not reason.is_empty():
		take.text = reason

	var row := Widgets.row([left, right, take], 16)
	row.tooltip_text = cargo.description
	return row


func _tags(contract: Contract) -> String:
	var names := PackedStringArray()
	for flag: StringName in contract.flags:
		match flag:
			&"urgent": names.append("срочно")
			&"fragile": names.append("хрупкое")
			&"cold": names.append("боится жары")
			&"restricted": names.append("без маркировки")
	if contract.story_id != &"":
		names.append("личная просьба")
	return " · ".join(names)


# --- Сдача -----------------------------------------------------------------

func _build_deliver() -> Control:
	var column := VBoxContainer.new()
	column.name = "Сдать груз"
	column.add_theme_constant_override("separation", 6)

	var ready := ContractBoard.deliverable(settlement)
	if ready.is_empty():
		column.add_child(Widgets.label("Сюда вы ничего не везёте.", 14, UiTheme.INK_DIM))
		var carrying := GameState.active_contracts()
		for contract: Contract in carrying:
			var destination := World.settlement(contract.destination_id)
			column.add_child(
				Widgets.field(
					"%s ×%d" % [contract.cargo().display_name, contract.units],
					"ждут в %s" % destination.display_name
				)
			)
		return Widgets.scroll(column)

	var now := GameState.total_hours()
	for contract: Contract in ready:
		var late := contract.hours_left(now) < 0.0
		var payout := contract.payout_at(now)
		var left := Widgets.column([
			Widgets.label("%s ×%d" % [contract.cargo().display_name, contract.units], 16),
			Widgets.label(
				"целостность %d%%%s"
				% [
					roundi(contract.integrity * 100.0),
					"   опоздание %.1f ч" % -contract.hours_left(now) if late else ""
				],
				13, UiTheme.DANGER if late or contract.integrity < 0.8 else UiTheme.INK_DIM
			),
		], 2)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var amount := Widgets.label(Settings.format_money(payout), 17, UiTheme.SAND)
		var do_deliver := func() -> void:
			_show_receipt(contract, ContractBoard.deliver(contract, vehicle))
		var hand_over := Widgets.button("Сдать", do_deliver)
		column.add_child(Widgets.row([left, amount, hand_over], 16))
		column.add_child(Widgets.separator())
	return Widgets.scroll(column)


## Разбор расчёта после сдачи. Игрок должен видеть, за что именно недоплатили,
## иначе штраф за помятый груз выглядит произволом.
func _show_receipt(contract: Contract, report: Dictionary) -> void:
	var lines := PackedStringArray()
	lines.append("Договор: %s" % Settings.format_money(float(report["gross"])))
	if float(report["integrity_loss"]) > 1.0:
		lines.append("Порча груза: −%s" % Settings.format_money(float(report["integrity_loss"])))
	if float(report["late_loss"]) > 1.0:
		lines.append(
			"Опоздание на %.1f ч: −%s"
			% [float(report["late_hours"]), Settings.format_money(float(report["late_loss"]))]
		)
	if float(report["damage_charge"]) > 1.0:
		lines.append("Удержано из залога: −%s" % Settings.format_money(float(report["damage_charge"])))
	lines.append("Возврат залога: %s" % Settings.format_money(float(report["deposit_returned"])))
	lines.append("Итого на руки: %s" % Settings.format_money(
		float(report["payout"]) + float(report["deposit_returned"])
	))
	EventBus.notify("%s — %s" % [contract.cargo().display_name, lines[lines.size() - 1]], &"good")
	_reopen(Tab.DELIVER)
	body.add_child(Widgets.panel(Widgets.column(_to_labels(lines)), UiTheme.PANEL_SOFT))


func _to_labels(lines: PackedStringArray) -> Array[Control]:
	var out: Array[Control] = []
	for line: String in lines:
		out.append(Widgets.label(line, 13, UiTheme.INK_DIM))
	return out


# --- Услуги ----------------------------------------------------------------

func _build_services() -> Control:
	var column := VBoxContainer.new()
	column.name = "Услуги"
	column.add_theme_constant_override("separation", 10)

	if settlement.has_service(&"fuel"):
		var price := Economy.fuel_price(settlement)
		var full := Economy.full_tank_cost(settlement, vehicle)
		column.add_child(Widgets.label("Топливо — %.2f дх за литр" % price, 15, UiTheme.SAND))
		var fill_tank := func() -> void:
			Economy.refuel(settlement, vehicle, vehicle.config.fuel_capacity)
			_reopen(Tab.SERVICES)
		var fill_fifty := func() -> void:
			Economy.refuel(settlement, vehicle, 50.0)
			_reopen(Tab.SERVICES)
		column.add_child(
			Widgets.row([
				Widgets.button("Полный бак (%s)" % Settings.format_money(full), fill_tank),
				Widgets.button("50 л", fill_fifty),
			])
		)
	else:
		column.add_child(Widgets.label("Топлива здесь нет.", 14, UiTheme.INK_FAINT))

	column.add_child(Widgets.separator())

	if settlement.has_service(&"repair"):
		column.add_child(Widgets.label("Мастерская", 15, UiTheme.SAND))
		for line: Dictionary in Economy.repair_quote(vehicle):
			var condition := float(line["condition"])
			var status := Widgets.gauge(
				String(line["title"]), condition, "%d%%" % roundi(condition * 100.0)
			)
			status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var component := StringName(line["id"])
			var do_repair := func() -> void:
				Economy.repair(settlement, vehicle, component)
				_reopen(Tab.SERVICES)
			var fix := Widgets.button(
				"%s · %.1f ч" % [Settings.format_money(float(line["cost"])), float(line["hours"])],
				do_repair
			)
			fix.disabled = not bool(line["needed"])
			if not bool(line["needed"]):
				fix.text = "в порядке"
			column.add_child(Widgets.row([status, fix], 16))
	else:
		column.add_child(Widgets.label("Мастерской здесь нет.", 14, UiTheme.INK_FAINT))

	column.add_child(Widgets.separator())

	if settlement.has_service(&"bunk"):
		column.add_child(Widgets.label("Ночлег", 15, UiTheme.SAND))
		var rest_row: Array[Control] = []
		for hours: int in [4, 8]:
			var cost := Economy.rest_cost(settlement, float(hours))
			var span := float(hours)
			var do_rest := func() -> void:
				Economy.rest(settlement, span)
				_reopen(Tab.SERVICES)
			rest_row.append(
				Widgets.button("%d ч · %s" % [hours, Settings.format_money(cost)], do_rest)
			)
		column.add_child(Widgets.row(rest_row))
		column.add_child(
			Widgets.caption("Груз портится и во сне: скоропортящееся лучше довезти до отдыха.")
		)
	return Widgets.scroll(column)


# --- Гараж -----------------------------------------------------------------

func _build_garage() -> Control:
	var column := VBoxContainer.new()
	column.name = "Гараж"
	column.add_theme_constant_override("separation", 8)

	column.add_child(Widgets.label("Давление в шинах", 15, UiTheme.SAND))
	var pressure := vehicle.wheels[0].pressure if vehicle != null else 2.4
	var slider := HSlider.new()
	slider.min_value = vehicle.config.pressure_min
	slider.max_value = vehicle.config.pressure_max
	slider.step = 0.1
	slider.value = pressure
	slider.custom_minimum_size = Vector2(320.0, 0.0)
	var readout := Widgets.label("%.1f бар" % pressure, 15, UiTheme.INK)
	slider.value_changed.connect(func(value: float) -> void:
		vehicle.set_pressure_all(value)
		readout.text = "%.1f бар" % value
	)
	column.add_child(Widgets.row([slider, readout], 12))
	column.add_child(
		Widgets.wrapped(
			"Ниже полутора бар пятно контакта растёт вдвое: по дюнам машина едет,"
			+ " а не закапывается. На камне и накатке спущенные колёса греются и"
			+ " быстрее изнашиваются, поэтому перед твёрдой дорогой их подкачивают."
		)
	)

	column.add_child(Widgets.separator())
	column.add_child(Widgets.label("Оборудование", 15, UiTheme.SAND))
	for item: Dictionary in Upgrades.all():
		var id := StringName(item.get("id", ""))
		var owned := Upgrades.has(id)
		var info := Widgets.column([
			Widgets.label(String(item.get("name", "")), 15, UiTheme.INK),
			Widgets.wrapped(String(item.get("description", ""))),
		], 2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var price := float(item.get("price", 0.0))
		var do_buy := func() -> void:
			if Upgrades.buy(id):
				_reopen(Tab.GARAGE)
		var buy := Widgets.button("стоит" if owned else Settings.format_money(price), do_buy)
		buy.disabled = owned or not GameState.can_afford(price)
		column.add_child(Widgets.row([info, buy], 16))
		column.add_child(Widgets.separator())
	return Widgets.scroll(column)
