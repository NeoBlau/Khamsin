class_name VehicleInput
extends RefCounted
## Что попросили у машины на этом кадре.
##
## Отдельный объект, потому что источников три: игрок, автопилот-эвакуатор и
## стенд телеметрии. Физика не должна знать, кто именно давит на газ.

var throttle: float = 0.0
var brake: float = 0.0
## -1 влево, +1 вправо.
var steer: float = 0.0
var handbrake: float = 0.0
## 0 — сцепление выжато полностью, 1 — схвачено.
var clutch: float = 1.0
var shift_up: bool = false
var shift_down: bool = false
var ignition: bool = true
var starter: bool = false


## Копирует команду в другой объект. Физика работает с копией, чтобы помощники
## (АБС, противобуксовочная) резали газ, не затирая то, что просил игрок.
func copy_to(other: VehicleInput) -> void:
	other.throttle = throttle
	other.brake = brake
	other.steer = steer
	other.handbrake = handbrake
	other.clutch = clutch
	other.shift_up = shift_up
	other.shift_down = shift_down
	other.ignition = ignition
	other.starter = starter


func clear_edges() -> void:
	shift_up = false
	shift_down = false
	starter = false


func reset() -> void:
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	handbrake = 0.0
	clutch = 1.0
	clear_edges()
