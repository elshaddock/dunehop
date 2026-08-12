extends StaticBody3D

## Breaks under a footdrum and nothing else, so the drum has a reason to exist beyond
## being a fast way down.
##
## Nothing about a flat panel says "stomp me", and a drum landing out of range used to be
## indistinguishable from drumming on bare sand, so the one mechanic that opens it was easy
## to never connect. It is now visibly fractured, and it rattles when a drum lands nearby but
## too far away, which points at the answer without giving it away.

@export var collapse_time := 0.28
@export var rattle_time := 0.34

var _broken := false
var _rattling := false

@onready var _shape: CollisionShape3D = $Collision


func _ready() -> void:
	add_to_group("drummable")


func on_drum(_origin: Vector3) -> void:
	if _broken:
		return
	_broken = true
	# Drop collision on the same frame so the drum carries straight through.
	_shape.disabled = true
	Sfx.play_at("slab_break", global_position, 1.0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3(1.0, 0.05, 1.0), collapse_time)
	tween.tween_property(self, "position:y", position.y - 0.5, collapse_time)
	tween.chain().tween_callback(queue_free)


## Close, but not close enough. Shudder so the player learns where the drum has to land.
func on_drum_nearby(_origin: Vector3) -> void:
	if _broken or _rattling:
		return
	_rattling = true
	Sfx.play_at("slab_rattle", global_position, -6.0)

	var rest := position.y
	var tween := create_tween()
	tween.tween_property(self, "position:y", rest + 0.07, rattle_time * 0.22)
	tween.tween_property(self, "position:y", rest, rattle_time * 0.3)
	tween.tween_property(self, "position:y", rest + 0.03, rattle_time * 0.2)
	tween.tween_property(self, "position:y", rest, rattle_time * 0.28)
	tween.tween_callback(func() -> void: _rattling = false)
