extends Node

## Throwaway visual check. The creature proxy and the level were authored as text without
## ever being looked at, so this renders a few framings to disk.
##
##   godot --path . res://tests/shots.tscn

var player: CharacterBody3D
var cam: Camera3D


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	player = main.get_node("Player")
	player.get_node("CamPivot").set("align_min_speed", 9999.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	cam = Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()

	await settle(20)

	# Hop stance, upright.
	set_stance(1, 2)
	await settle(30)
	await portrait("hop", Vector3(1.7, 1.05, 2.0))

	# Scurry stance, pitched down onto all fours.
	set_stance(0, 0)
	await settle(40)
	await portrait("scurry", Vector3(1.7, 0.85, 2.0))

	# Parasail, ears spread. The state exits immediately unless leap is genuinely held,
	# and it lands unless the creature stays off the floor, so hover it with zeroed drift.
	player.parasail_fall_speed = 0.0
	player.parasail_forward = 0.0
	player.global_position += Vector3(0, 1.6, 0)
	player.velocity = Vector3.ZERO
	Input.action_press("leap")
	set_stance(1, 5)
	await settle(45)
	await portrait("parasail", Vector3(1.9, 1.1, 2.2))
	Input.action_release("leap")

	# Gameplay framing looking down the conversion runway at the raised ledge.
	player.global_position = Vector3(0, 0.4, 20)
	set_stance(0, 0)
	await settle(30)
	cam.global_position = Vector3(0, 6.0, 8.0)
	cam.look_at(Vector3(0, 2.0, 46.0))
	await capture("conversion_gap")

	# Whole level from above.
	cam.global_position = Vector3(46, 62, 30)
	cam.look_at(Vector3(-6, 0, -18))
	await capture("overview")

	get_tree().quit()


func set_stance(stance: int, state: int) -> void:
	player._apply_stance(stance)
	player.state = state


func portrait(name: String, offset: Vector3) -> void:
	var focus: Vector3 = player.global_position + Vector3(0, 0.62, 0)
	cam.global_position = player.global_position + offset
	cam.look_at(focus)
	await capture(name)


func capture(name: String) -> void:
	await settle(4)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("res://tests/shot_%s.png" % name)
	print("wrote shot_%s.png" % name)


func settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
