extends Area3D

## A toll that spends banked seeds to open a route.
##
## This is what the burrow was always for. Banking seeds only becomes a decision once there
## is somewhere for them to go, and until this existed the pouch cap, the spill on falls and
## the weight penalty were all cost with no matching payoff.
##
## Paying is done by standing here rather than by a keypress. Walking onto a toll is already
## a deliberate act, it needs no free key on a crowded pad, it reads clearly because the
## barrier sinks as the count drops, and stepping off stops it. Seeds already handed over
## stay handed over, so an interrupted payment is progress rather than a loss.

signal payment_changed(paid: int, cost: int)
signal opened()

@export var cost := 20
@export var seeds_per_second := 9.0
## How far the barrier sinks once fully paid. Must exceed its own height or it will still
## be poking out of the floor when the toll is settled.
@export var open_drop := 2.8
@export var open_time := 0.45
@export var label := "Warden's Gate"

var _paid := 0
var _change := 0.0
var _open := false
var _barrier_rest := 0.0
var _material: StandardMaterial3D = null

@onready var _barrier: StaticBody3D = $Barrier
@onready var _collision: CollisionShape3D = $Barrier/Collision
@onready var _mesh: MeshInstance3D = $Barrier/Mesh


func _ready() -> void:
	add_to_group("seed_gate")
	_barrier_rest = _barrier.position.y
	# Own copy so brightening this gate cannot bleed into any other.
	_material = _mesh.mesh.surface_get_material(0).duplicate()
	_mesh.set_surface_override_material(0, _material)


func is_open() -> bool:
	return _open


func paid() -> int:
	return _paid


func remaining() -> int:
	return maxi(0, cost - _paid)


## True when the player is stood on the toll, which is what the HUD keys its prompt off.
func player_present() -> bool:
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false


func _physics_process(delta: float) -> void:
	if _open or not player_present():
		_change = 0.0
		return

	_change += seeds_per_second * delta
	var spent := 0
	while _change >= 1.0 and _paid < cost:
		if GameState.spend_stored(1) <= 0:
			# Out of banked seeds. Hold the change so arriving with more resumes cleanly.
			_change = 0.0
			break
		_change -= 1.0
		_paid += 1
		spent += 1

	if spent > 0:
		payment_changed.emit(_paid, cost)
		_brighten()
		# Rises as the toll fills, so the last few seeds sound like the end of something.
		var ratio := float(_paid) / float(maxi(1, cost))
		Sfx.play_at("toll_tick", global_position, -13.0, lerpf(0.9, 1.5, ratio))
	if _paid >= cost:
		_finish()


## Progress is shown by the barrier lighting up rather than by sinking.
##
## Sinking it proportionally was the obvious choice and it was wrong: the doorway is 2.0 tall
## and the barrier 2.2, so by 29% paid the gap above it already exceeded the 0.6 scurry
## height and you could simply crawl over the top. The feedback was the exploit. A shut gate
## now stays shut, and the drop happens once, as the payoff.
func _brighten() -> void:
	var ratio := float(_paid) / float(maxi(1, cost))
	_material.emission_energy_multiplier = lerpf(0.5, 3.2, ratio)


func _finish() -> void:
	_open = true
	Sfx.play_at("gate_open", global_position, -3.0)
	var tween := create_tween()
	tween.tween_property(_barrier, "position:y", _barrier_rest - open_drop, open_time)
	tween.tween_callback(func() -> void: _collision.disabled = true)
	opened.emit()
