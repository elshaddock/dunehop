extends StaticBody3D

## Breaks under a footdrum and nothing else, so the drum has a reason to exist beyond
## being a fast way down.

@export var collapse_time := 0.28

var _broken := false

@onready var _shape: CollisionShape3D = $Collision


func _ready() -> void:
	add_to_group("drummable")


func on_drum(_origin: Vector3) -> void:
	if _broken:
		return
	_broken = true
	# Drop collision on the same frame so the drum carries straight through.
	_shape.disabled = true

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3(1.0, 0.05, 1.0), collapse_time)
	tween.tween_property(self, "position:y", position.y - 0.5, collapse_time)
	tween.chain().tween_callback(queue_free)
