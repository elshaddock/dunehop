extends Node3D

## A spat seed.
##
## Integrated by hand instead of as a RigidBody3D so the arc is a number the level can be
## dimensioned against rather than a physics accident, and swept with a raycast between the
## previous and current position so a fast shot cannot tunnel through a small target.

signal hit_target(target: Node3D)

@export var speed := 19.0
## Lighter than the player's gravity so the arc stays long and readable at a glance.
@export var shot_gravity := 9.0
@export var lifetime := 3.0
@export var fade_time := 0.14

var _velocity := Vector3.ZERO
var _life := 0.0
var _spent := false
var _exclude: Array[RID] = []

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	add_to_group("seed_shot")


## Must be called after the shot is in the tree, since it places it in world space.
func launch(from: Vector3, dir: Vector3, ignore: RID = RID()) -> void:
	global_position = from
	_velocity = dir.normalized() * speed
	if ignore.is_valid():
		_exclude = [ignore]
	_face_travel()


func _physics_process(delta: float) -> void:
	if _spent:
		return

	_life += delta
	if _life >= lifetime:
		_finish()
		return

	_velocity.y -= shot_gravity * delta
	var from := global_position
	var to := from + _velocity * delta

	var hit := _sweep(from, to)
	if hit.is_empty():
		global_position = to
		_face_travel()
		return

	global_position = hit["position"]
	var collider := hit["collider"] as Node3D
	if collider != null and collider.has_method("on_spit"):
		collider.on_spit(from)
		hit_target.emit(collider)
	_finish()


## Layer 1 is the world, layer 2 is spit targets. Targets are kept off the world layer so
## they never become accidental platforms.
func _sweep(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 2
	query.exclude = _exclude
	return get_world_3d().direct_space_state.intersect_ray(query)


func _face_travel() -> void:
	if _velocity.length_squared() < 0.01:
		return
	look_at(global_position + _velocity, Vector3.UP)


func _finish() -> void:
	_spent = true
	# Never scale to exactly zero: a zero basis is singular and the servers complain loudly
	# when they try to invert it.
	var tween := create_tween()
	tween.tween_property(_mesh, "scale", Vector3.ONE * 0.02, fade_time)
	tween.tween_callback(queue_free)
