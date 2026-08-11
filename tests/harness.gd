extends Node

## Headless playtest harness. Drives the real player through the real level with
## simulated input so the level's gating is verified by measurement rather than by
## trusting the arithmetic that produced the dimensions.
##
## Run with a fixed timestep so results are deterministic:
##   godot --headless --fixed-fps 60 --path . res://tests/harness.tscn

const ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right",
	"leap", "swap_stance", "drum", "tail_twist",
]

const STANCE_SCURRY := 0
const STANCE_HOP := 1
const STATE_SCURRY_GROUND := 0
const STATE_HOP_GROUND := 2

## Conversion runway ends at z = 35; the landing ledge top is y = 3 spanning z = 42..58.
const TAKEOFF_Z := 34.3
const LEDGE_Z := 42.0

var player: CharacterBody3D
var failures := 0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	player = main.get_node("Player")

	# Auto-align would rotate the camera mid-test and silently change what "forward"
	# means, and respawning would teleport the subject out from under a measurement.
	player.get_node("CamPivot").set("align_min_speed", 9999.0)
	player.kill_y = -400.0

	await steps(5)
	await run_all()

	print("")
	print("ALL CHECKS PASSED" if failures == 0 else "%d CHECK(S) FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func run_all() -> void:
	await check_scurry_top_speed()
	await check_trail_boost()
	await check_hop_ground_is_slower()
	await check_standing_leap_fails_gap()
	await check_standing_parasail_fails_gap()
	await check_scurry_hop_fails_gap()
	await check_converted_leap_clears_gap()
	await check_tunnel_blocks_hop()
	await check_tunnel_passable_scurrying()
	await check_high_ledge_needs_full_charge()
	await check_parasail_reaches_pad()
	await check_ballistic_misses_pad()
	await check_drum_breaks_slab()


# --- checks ------------------------------------------------------------------


func check_scurry_top_speed() -> void:
	# Run across the plaza rather than down the runway, which is carpeted with trail.
	await reset(Vector3(-13, 0.4, 0), STANCE_SCURRY)
	Input.action_press("move_right")
	await steps(90)
	var speed: float = player.horizontal_speed()
	release_all()
	report("scurry reaches top speed off-trail", speed > 10.5 and speed < 11.6, "%.2f u/s" % speed)


func check_trail_boost() -> void:
	await reset(Vector3(0, 0.4, -20), STANCE_SCURRY)
	Input.action_press("move_forward")
	await steps(120)
	var speed: float = player.horizontal_speed()
	var on_trail: bool = player.on_trail
	release_all()
	report(
		"a cleared trail raises the scurry cap",
		on_trail and speed > 14.0,
		"%.2f u/s, on_trail=%s" % [speed, on_trail]
	)


func check_hop_ground_is_slower() -> void:
	await reset(Vector3(0, 0.4, 0), STANCE_HOP)
	Input.action_press("move_forward")
	await steps(150)
	var speed: float = player.horizontal_speed()
	release_all()
	report("hop stance is much slower on the ground", speed < 5.0, "%.2f u/s" % speed)


func check_standing_leap_fails_gap() -> void:
	var result := await leap_from(Vector3(0, 0.4, TAKEOFF_Z), 0.75, false)
	report(
		"standing charged leap does NOT clear the conversion gap",
		not result.on_ledge,
		"reached z=%.2f y=%.2f" % [result.pos.z, result.pos.y]
	)


func check_standing_parasail_fails_gap() -> void:
	var result := await leap_from(Vector3(0, 0.4, TAKEOFF_Z), 0.75, true)
	report(
		"standing leap plus parasail does NOT clear the conversion gap",
		not result.on_ledge,
		"reached z=%.2f y=%.2f" % [result.pos.z, result.pos.y]
	)


func check_scurry_hop_fails_gap() -> void:
	await reset(Vector3(0, 0.4, 14.0), STANCE_SCURRY)
	Input.action_press("move_back")
	await run_until_z(TAKEOFF_Z)
	await press_tap("leap")
	var result := await settle(300)
	release_all()
	report(
		"full-speed scurry hop does NOT clear the conversion gap",
		not result.on_ledge,
		"reached z=%.2f y=%.2f" % [result.pos.z, result.pos.y]
	)


func check_converted_leap_clears_gap() -> void:
	await reset(Vector3(0, 0.4, 14.0), STANCE_SCURRY)
	Input.action_press("move_back")
	await run_until_z(TAKEOFF_Z)
	var ran_at: float = player.horizontal_speed()
	await press_tap("swap_stance")
	var banked: float = player.momentum_speed
	await press_tap("leap")
	var result := await settle(300)
	release_all()
	report(
		"converted leap DOES clear the conversion gap",
		result.on_ledge,
		"ran %.1f, banked %.1f, landed z=%.2f y=%.2f" % [ran_at, banked, result.pos.z, result.pos.y]
	)


func check_tunnel_blocks_hop() -> void:
	# Inside the 0.8-high tunnel mouth there is no room to stand up.
	await reset(Vector3(19.5, 0.05, 0), STANCE_SCURRY)
	await steps(6)
	await press_tap("swap_stance")
	await steps(4)
	var stance: int = player.stance
	release_all()
	report("tunnel mouth blocks standing up into hop", stance == STANCE_SCURRY, "stance=%d" % stance)


func check_tunnel_passable_scurrying() -> void:
	await reset(Vector3(15.5, 0.4, 0), STANCE_SCURRY)
	Input.action_press("move_right")
	await steps(200)
	var x: float = player.global_position.x
	release_all()
	report("scurry passes through the tunnel into the room", x > 21.0, "reached x=%.2f" % x)


func check_high_ledge_needs_full_charge() -> void:
	# Tier 1 top sits at y = 4.5, just under the 5.0 maximum leap.
	var short_charge := await vertical_leap(Vector3(-15.5, 0.4, 0), 0.25)
	var full_charge := await vertical_leap(Vector3(-15.5, 0.4, 0), 0.75)
	report("a short charge cannot reach the 4.5 ledge", short_charge < 4.5, "apex %.2f" % short_charge)
	report("a full charge can reach the 4.5 ledge", full_charge >= 4.5, "apex %.2f" % full_charge)


func check_parasail_reaches_pad() -> void:
	# Tier 3 top is y = 10.7; the pad top is y = 2 with its near edge 16.2 units away.
	var result := await leap_from(Vector3(-22, 11.0, -1.0), 0.75, true)
	report(
		"parasail reaches the offset pad",
		result.pos.y > 1.5 and result.pos.z < -18.0,
		"landed z=%.2f y=%.2f" % [result.pos.z, result.pos.y]
	)


func check_ballistic_misses_pad() -> void:
	var result := await leap_from(Vector3(-22, 11.0, -1.0), 0.75, false)
	report(
		"the same leap without parasail falls short of the pad",
		result.pos.y < 1.5 or result.pos.z > -18.0,
		"ended z=%.2f y=%.2f" % [result.pos.z, result.pos.y]
	)


func check_drum_breaks_slab() -> void:
	var slab: Node = get_node_or_null("Main/CrackedSlab")
	await reset(Vector3(9, 0.5, 8), STANCE_HOP)
	await steps(10)
	# Leap straight up off the slab, then slam back down onto it.
	Input.action_press("leap")
	await steps(45)
	Input.action_release("leap")
	while player.velocity.y > 0.0:
		await get_tree().physics_frame
	await press_tap("drum")
	await steps(220)
	var y: float = player.global_position.y
	var gone: bool = slab == null or not is_instance_valid(slab)
	release_all()
	report(
		"footdrum breaks the cracked slab and drops into the vault",
		gone and y < -2.0,
		"y=%.2f slab_gone=%s" % [y, gone]
	)


# --- driving helpers ---------------------------------------------------------


## Charge a leap from a standing start, optionally parasailing once past the apex.
func leap_from(from: Vector3, charge_seconds: float, parasail: bool) -> Dictionary:
	await reset(from, STANCE_HOP)
	await steps(6)
	Input.action_press("leap")
	await steps(int(charge_seconds * 60.0))
	Input.action_release("leap")
	# The launch happens on release, so wait for it before touching leap again or the
	# re-press just resumes charging and the player never leaves the ground.
	for i in 30:
		await get_tree().physics_frame
		if player.velocity.y > 0.0:
			break
	# Hold the travel direction so air steering pushes toward the target.
	Input.action_press("move_forward" if from.z < 0.0 else "move_back")
	if parasail:
		while player.velocity.y > 0.0:
			await get_tree().physics_frame
		Input.action_press("leap")
	var result := await settle(900)
	release_all()
	return result


## Measure peak height gained from a standing charged leap.
func vertical_leap(from: Vector3, charge_seconds: float) -> float:
	await reset(from, STANCE_HOP)
	await steps(6)
	var base: float = player.global_position.y
	Input.action_press("leap")
	await steps(int(charge_seconds * 60.0))
	Input.action_release("leap")
	var peak := base
	for i in 250:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
		if player.velocity.y < 0.0 and player.is_on_floor():
			break
	release_all()
	return peak - base


func run_until_z(target: float) -> void:
	for i in 600:
		await get_tree().physics_frame
		if player.global_position.z >= target:
			return


## Run until the player is resting on something, then report where.
func settle(max_frames: int) -> Dictionary:
	var resting := 0
	for i in max_frames:
		await get_tree().physics_frame
		if player.is_on_floor():
			resting += 1
			if resting > 8:
				break
		else:
			resting = 0
		if player.global_position.y < -20.0:
			break
	var pos: Vector3 = player.global_position
	return {"pos": pos, "on_ledge": pos.y > 2.5 and pos.z > LEDGE_Z - 0.5}


func reset(pos: Vector3, stance: int) -> void:
	release_all()
	player.velocity = Vector3.ZERO
	player.global_position = pos
	player.momentum_speed = 0.0
	player.momentum_timer = 0.0
	player.momentum_charge = 0.0
	player.charge = 0.0
	player.twist_used = false
	player.on_trail = false
	player._apply_stance(stance)
	player.state = STATE_SCURRY_GROUND if stance == STANCE_SCURRY else STATE_HOP_GROUND
	await steps(2)


func steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func press_tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func release_all() -> void:
	for action in ACTIONS:
		Input.action_release(action)


func report(label: String, passed: bool, detail: String) -> void:
	if not passed:
		failures += 1
	print("%s  %s  (%s)" % ["PASS" if passed else "FAIL", label, detail])
