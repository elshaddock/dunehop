extends StaticBody3D

## A seed pod, hung out of reach and openable only by spitting at it.
##
## This is what stops the spit from being a pure tax. One seed spent on a well-aimed shot
## pays back several, so ammunition is an investment and the interesting question becomes
## whether you trust your aim, not whether you can afford to shoot.
##
## Pods regrow, because a prototype where missing can permanently destroy your own
## ammunition supply is a prototype you can softlock.

const SEED := preload("res://scenes/seed.tscn")

@export var seed_yield := 3
@export var burst_time := 0.24
## Set to zero for a one-shot pod.
@export var regrow_time := 12.0
@export var scatter_radius := 1.0
## How far down to look for somewhere to drop the contents.
@export var drop_probe := 80.0

var _burst := false
var _regrow_timer: Timer

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $Collision


func _ready() -> void:
	add_to_group("spittable")
	# A Timer node rather than an awaited SceneTreeTimer: the tree owns it, so a pod caught
	# mid-regrow at shutdown does not leave a suspended coroutine behind.
	_regrow_timer = Timer.new()
	_regrow_timer.one_shot = true
	_regrow_timer.timeout.connect(_regrow)
	add_child(_regrow_timer)


func on_spit(_from: Vector3) -> void:
	if _burst:
		return
	_burst = true
	_shape.disabled = true
	_scatter()

	var tween := create_tween()
	tween.tween_property(_mesh, "scale", Vector3.ONE * 1.6, burst_time * 0.35)
	tween.tween_property(_mesh, "scale", Vector3.ONE * 0.02, burst_time * 0.65)
	tween.tween_callback(_wait_to_regrow)


## Rain the contents onto whatever floor is underneath rather than leaving them hanging in
## the air where the pod was, since pods are placed precisely where you cannot stand.
func _scatter() -> void:
	var ground := _ground_below()
	var host := get_parent()
	if host == null:
		return
	for i in seed_yield:
		var angle := TAU * float(i) / float(maxi(seed_yield, 1))
		var spot := ground + Vector3(cos(angle), 0.0, sin(angle)) * scatter_radius + Vector3.UP * 0.9
		var pip: Node3D = SEED.instantiate()
		# Pod seeds are created, not placed, so they must not inflate the level's tally.
		pip.set("bonus", true)
		# Position before adding: the pickup samples its own height on entering the tree to
		# know what to bob around.
		pip.position = host.to_local(spot) if host is Node3D else spot
		host.add_child(pip)


func _ground_below() -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * drop_probe
	)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return global_position
	return hit["position"]


func _wait_to_regrow() -> void:
	_mesh.visible = false
	if regrow_time <= 0.0:
		queue_free()
		return
	_regrow_timer.start(regrow_time)


func _regrow() -> void:
	_mesh.scale = Vector3.ONE * 0.02
	_mesh.visible = true
	var tween := create_tween()
	tween.tween_property(_mesh, "scale", Vector3.ONE, 0.32)
	tween.tween_callback(_arm)


func _arm() -> void:
	_shape.disabled = false
	_burst = false
