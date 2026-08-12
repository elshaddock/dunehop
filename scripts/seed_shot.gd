class_name SeedShot
extends Node3D

## A spat seed.
##
## Integrated by hand instead of as a RigidBody3D so the arc is a number the level can be
## dimensioned against rather than a physics accident, and swept with a raycast between the
## previous and current position so a fast shot cannot tunnel through a small target.
##
## The defaults here are only fallbacks. The player owns the real tuning and applies it at
## launch, so the reticle it draws and the shot it fires cannot drift apart.

signal impacted(point: Vector3, collider: Node3D)

@export var speed := 30.0
## Much lighter than the player's gravity: the arc still reads, but a seat-of-the-pants shot
## carries about twenty units instead of dribbling into the sand ten units ahead.
@export var shot_gravity := 6.0
@export var lifetime := 3.0
@export var fade_time := 0.1

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
		_finish(global_position, null)
		return

	_velocity.y -= shot_gravity * delta
	var from := global_position
	var to := from + _velocity * delta

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = Ballistics.SPIT_MASK
	query.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		global_position = to
		_face_travel()
		return

	var point: Vector3 = hit["position"]
	global_position = point
	var collider := hit["collider"] as Node3D
	if collider != null and collider.has_method("on_spit"):
		collider.on_spit(from)
	_finish(point, collider)


func _face_travel() -> void:
	if _velocity.length_squared() < 0.01:
		return
	look_at(global_position + _velocity, Vector3.UP)


func _finish(point: Vector3, collider: Node3D) -> void:
	_spent = true
	impacted.emit(point, collider)
	_puff(point)
	if collider != null:
		Sfx.play_at("shot_hit", point, -11.0, randf_range(0.9, 1.15))

	# Never scale to exactly zero: a zero basis is singular and the servers complain loudly
	# when they try to invert it.
	var tween := create_tween()
	tween.tween_property(_mesh, "scale", Vector3.ONE * 0.02, fade_time)
	tween.tween_callback(queue_free)


## Something has to say "that landed there", or a missed shot simply vanishes and the player
## learns nothing about why.
func _puff(point: Vector3) -> void:
	var host := get_parent()
	if host == null:
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.98, 0.88, 0.6, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = material

	var puff := MeshInstance3D.new()
	puff.mesh = sphere
	host.add_child(puff)
	puff.global_position = point

	var tween := puff.create_tween()
	tween.set_parallel(true)
	tween.tween_property(puff, "scale", Vector3.ONE * 3.4, 0.24)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.24)
	tween.chain().tween_callback(puff.queue_free)
