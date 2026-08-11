extends Area3D

## Spinning pickup. Registers itself with GameState on spawn so the HUD gets a
## denominator without the level maintaining a hand-written count.

@export var spin_speed := 2.2
@export var bob_height := 0.16
@export var bob_speed := 2.6

var _base_y := 0.0
var _phase := 0.0
var _taken := false


func _ready() -> void:
	_base_y = position.y
	_phase = randf() * TAU
	GameState.register_seed()
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_phase += delta * bob_speed
	rotate_y(spin_speed * delta)
	position.y = _base_y + sin(_phase) * bob_height


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	GameState.collect_seed()
	set_deferred("monitoring", false)

	# Never tween all the way to zero: a zero scale makes the transform basis singular
	# and the physics server floods the log trying to invert it.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE * 0.02, 0.18)
	tween.tween_property(self, "position:y", _base_y + 0.8, 0.18)
	tween.chain().tween_callback(queue_free)
