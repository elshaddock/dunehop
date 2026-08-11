extends Area3D

## Spinning pickup.
##
## Refuses to be taken when the cheeks are full. Destroying a seed the player has no room
## for would read as a broken pickup, so it stays put and visibly bounces off instead, and
## re-offers itself the moment there is space again.

@export var spin_speed := 2.2
@export var bob_height := 0.16
@export var bob_speed := 2.6
## Seeds spilled out of a pod are created rather than placed, so they do not count toward
## the level's own tally.
@export var bonus := false

var _base_y := 0.0
var _phase := 0.0
var _taken := false
var _refusing := false


func _ready() -> void:
	_base_y = position.y
	_phase = randf() * TAU
	add_to_group("seed")
	if not bonus:
		GameState.register_seed()
	body_entered.connect(_on_body_entered)
	GameState.pouch_changed.connect(_on_pouch_changed)


func _process(delta: float) -> void:
	_phase += delta * bob_speed
	rotate_y(spin_speed * delta)
	position.y = _base_y + sin(_phase) * bob_height


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_try_take()


## Standing still on a refused seed produces no new body_entered, so a change in pouch
## space has to re-offer it.
func _on_pouch_changed(_pouch: int, _capacity: int) -> void:
	if _taken or GameState.is_pouch_full():
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_try_take()
			return


func _try_take() -> void:
	if _taken:
		return

	# Claim it before pocketing. pocket_seed() emits pouch_changed synchronously and this
	# seed listens to that signal in order to re-offer itself, so a seed that has not yet
	# marked itself taken will go on accepting itself until the pouch is full.
	_taken = true
	if not GameState.pocket_seed():
		_taken = false
		_refuse()
		return

	set_deferred("monitoring", false)

	# Never tween all the way to zero: a zero scale makes the transform basis singular and
	# the physics server floods the log trying to invert it.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE * 0.02, 0.18)
	tween.tween_property(self, "position:y", _base_y + 0.8, 0.18)
	tween.chain().tween_callback(queue_free)


func _refuse() -> void:
	if _refusing:
		return
	_refusing = true
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 1.4, 0.09)
	tween.tween_property(self, "scale", Vector3.ONE, 0.14)
	tween.tween_callback(func() -> void: _refusing = false)
