extends Node
## Шина событий между подсистемами, которые не должны знать друг о друге.
##
## Здесь только то, что действительно пересекает границы модулей. Всё локальное
## живёт сигналами на своих узлах: шина, в которую сваливают всё подряд,
## быстро превращается в глобальные переменные с лишним шагом.

# --- Машина ----------------------------------------------------------------

## Кузов получил удар. `severity` — величина перегрузки в g сверх порога.
signal vehicle_impact(severity: float, contact_point: Vector3)
## Двигатель заглох (обороты ниже холостых при включённом сцеплении).
signal engine_stalled()
signal gear_changed(gear: int)
## Ушёл ниже 10% бака или перегрелся — то, на что HUD должен мигать.
signal vehicle_warning(kind: StringName, active: bool)
signal vehicle_stuck_changed(stuck: bool)

# --- Мир -------------------------------------------------------------------

signal hour_passed(day: int, hour: float)
signal weather_changed(kind: StringName, intensity: float)
signal settlement_entered(settlement_id: StringName)
signal settlement_exited(settlement_id: StringName)

# --- Геймплей --------------------------------------------------------------

signal contract_offered(contract_id: StringName)
signal contract_accepted(contract_id: StringName)
signal contract_completed(contract_id: StringName, payout: float, on_time: bool)
signal contract_failed(contract_id: StringName, reason: StringName)
signal cargo_damaged(contract_id: StringName, integrity: float)
signal money_changed(amount: float, delta: float)
signal reputation_changed(faction: StringName, value: float)

# --- Сюжет -----------------------------------------------------------------

signal story_flag_set(flag: StringName, value: Variant)
signal chapter_started(chapter_id: StringName)
signal beat_reached(beat_id: StringName)
signal dialogue_requested(dialogue_id: StringName)
signal dialogue_finished(dialogue_id: StringName)

# --- Интерфейс -------------------------------------------------------------

signal notification_posted(text: String, kind: StringName)
signal screen_requested(screen: StringName, payload: Dictionary)
signal game_saved(slot: int)
signal game_loaded(slot: int)


## Короткий путь для тостов, чтобы не тащить строковый тип по всему коду.
func notify(text: String, kind: StringName = &"info") -> void:
	notification_posted.emit(text, kind)
