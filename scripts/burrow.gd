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

	# A tap per seed rather than one lump sound. Banking is the payoff for having carried a
	# full pouch across the level without falling, and a longer run of taps is a bigger one.
	var taps := mini(moved, 7)
	var run := create_tween()
	for i in taps:
		var step := float(i) / float(maxi(taps - 1, 1))
		run.tween_callback(
			func() -> void: Sfx.play_at("deposit", global_position, -9.0, lerpf(0.88, 1.44, step))
		)
		run.tween_interval(0.055)
