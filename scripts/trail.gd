extends Area3D

## A cleared sengi trail. Standing on one raises the scurry speed cap, which is the only
## way to bank enough momentum for the widest gap in the level.


func _ready() -> void:
	body_entered.connect(_on_changed.bind(true))
	body_exited.connect(_on_changed.bind(false))


func _on_changed(body: Node3D, entered: bool) -> void:
	if body.has_method("set_on_trail"):
		body.set_on_trail(entered)
