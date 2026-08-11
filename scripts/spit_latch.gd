extends StaticBody3D

## Spit target that sinks a gate out of the way, so the spit earns a traversal use instead
## of only feeding the economy.

signal opened

## Resolved by hand rather than exported as a typed Node, because a Node-typed export does
## not come back from the scene file here and fails silently as a null gate.
@export var gate_path: NodePath
@export var gate_offset := Vector3(0, -2.2, 0)
@export var open_time := 0.55

var gate: Node3D = null

var _open := false

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	add_to_group("spittable")
	if not gate_path.is_empty():
		gate = get_node_or_null(gate_path) as Node3D
	if gate == null:
		push_warning("SpitLatch at %s has no gate to open." % global_position)


func on_spit(_from: Vector3) -> void:
	if _open or gate == null:
		return
	_open = true
	_light()

	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(gate, "position", gate.position + gate_offset, open_time)
	tween.tween_callback(func() -> void: opened.emit())


## Latches are small and easy to lose against rock, so a hit has to announce itself.
func _light() -> void:
	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color(0.55, 0.85, 0.5)
	lit.emission_enabled = true
	lit.emission = Color(0.55, 0.85, 0.5)
	lit.emission_energy_multiplier = 2.0
	_mesh.material_override = lit
