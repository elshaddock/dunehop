extends Area3D

## The actual objective.
##
## Ordinary seeds are currency: renewable, spendable, and lost by the handful when you fall.
## A sunseed is none of those things. There is a fixed number of them, one behind each way
## the creature can move, and once taken it is yours. That split is what lets the seed
## counter stay loose and farmable while progress stays honest.

@export var spin_speed := 1.4
@export var bob_height := 0.16
@export var bob_speed := 2.2

## A shaft of light so the far-flung ones read as destinations from across the level. Turn it
## off for any sunseed under a roof, where the shaft would only be buried in the ceiling.
@export var beacon := true
@export var beacon_pulse := 0.5

var _taken := false
var _time := 0.0
var _base_y := 0.0
var _beacon_material: StandardMaterial3D = null

@onready var _pivot: Node3D = $Pivot
@onready var _beacon: MeshInstance3D = $Beacon


func _ready() -> void:
	GameState.register_sunseed()
	_base_y = _pivot.position.y
	# Desynchronise the bob so a cluster of them does not pulse in lockstep.
	_time = global_position.x + global_position.z
	body_entered.connect(_on_body_entered)

	_beacon.visible = beacon
	if beacon:
		# Own copy, or pulsing one shaft would pulse every shaft in the level.
		_beacon_material = _beacon.mesh.surface_get_material(0).duplicate()
		_beacon.set_surface_override_material(0, _beacon_material)


func _process(delta: float) -> void:
	if _taken:
		return
	_time += delta
	_pivot.rotate_y(spin_speed * delta)
	_pivot.position.y = _base_y + sin(_time * bob_speed) * bob_height

	if _beacon_material != null:
		var pulse := 0.5 + 0.5 * sin(_time * beacon_pulse * TAU)
		_beacon_material.albedo_color.a = lerpf(0.07, 0.17, pulse)


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	GameState.collect_sunseed()
	# Each one a step higher than the last, so the chime itself counts them for you.
	var step := float(GameState.sunseeds_found - 1) / float(maxi(1, GameState.sunseeds_total - 1))
	Sfx.play("sunseed", -6.0, lerpf(1.0, 1.5, clampf(step, 0.0, 1.0)))

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_pivot, "scale", Vector3.ONE * 2.4, 0.32)
	tween.tween_property(_pivot, "position:y", _base_y + 1.6, 0.32)
	if _beacon_material != null:
		tween.tween_property(_beacon_material, "albedo_color:a", 0.0, 0.28)
	# Never scale to exactly zero: a zero basis is singular and the servers complain.
	tween.chain().tween_property(_pivot, "scale", Vector3.ONE * 0.02, 0.14)
	tween.chain().tween_callback(queue_free)
