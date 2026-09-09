class_name CargoMonitor
extends Node
## Что происходит с грузом, пока он едет.
##
## Удары считает физика машины — это мгновенные события. Здесь всё медленное:
## жара, время, просрочка. Раз в игровой час груз стареет, а заказы, которые
## уже никому не нужны, снимаются.

## Температура, выше которой термочувствительный груз начинает портиться.
const HEAT_THRESHOLD := 34.0
## Доля целостности, теряемая за час при десяти градусах сверх порога.
const HEAT_RATE := 0.05

var weather: Weather
var vehicle: VehicleBody


func _ready() -> void:
	EventBus.hour_passed.connect(_on_hour_passed)


func _on_hour_passed(_day: int, _hour: float) -> void:
	_age_cargo()
	ContractBoard.expire_overdue()
	_warn_about_deadlines()


func _age_cargo() -> void:
	var temperature := weather.temperature if weather != null else 32.0
	for contract: Contract in GameState.active_contracts():
		var cargo := contract.cargo()
		if cargo == null:
			continue
		var damage := cargo.decay_per_hour
		if cargo.heat_sensitivity > 0.0 and temperature > HEAT_THRESHOLD:
			var excess := (temperature - HEAT_THRESHOLD) / 10.0
			damage += cargo.heat_sensitivity * excess * HEAT_RATE
		if damage > 0.0:
			contract.apply_damage(damage)


## Предупреждение за два часа до срока — ровно один раз на заказ.
func _warn_about_deadlines() -> void:
	var now := GameState.total_hours()
	for contract: Contract in GameState.active_contracts():
		var left := contract.hours_left(now)
		var flag := StringName("warned_%s" % contract.id)
		if left <= 2.0 and left > 0.0 and not bool(GameState.flag(flag, false)):
			GameState.set_flag(flag, true)
			EventBus.notify(
				"%s: до срока меньше двух часов" % contract.cargo().display_name, &"warning"
			)
