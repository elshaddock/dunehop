extends Area3D

## Deposit point. Standing on it empties the cheeks into permanent storage.
##
## Overlap is polled rather than driven by body_entered, because entering is not the only
## moment that matters: arriving empty and then wanting to bank later is normal, and an
## enter-only signal would silently refuse to fire the second time.

signal deposited(count: int)

## Small gap between deposits so a full pouch banks as one event, not a stream of them.
@export var interval := 0.25

var _cooldown := 0.0

@onready var _mound: Node3D = $Mound


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown > 0.0 or GameState.pouch <= 0:
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_bank()
			return


func _bank() -> void:
	var moved := GameState.deposit_pouch()
	if moved <= 0:
		return
	_cooldown = interval
	deposited.emit(moved)

	var tween := create_tween()
	tween.tween_property(_mound, "scale", Vector3(1.16, 0.78, 1.16), 0.09)
	tween.tween_property(_mound, "scale", Vector3.ONE, 0.18)
