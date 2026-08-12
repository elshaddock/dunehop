extends Node

## Headless playtest harness. Drives the real player through the real level with
## simulated input so the level's gating is verified by measurement rather than by
## trusting the arithmetic that produced the dimensions.
##
## Run with a fixed timestep so results are deterministic:
##   godot --headless --fixed-fps 60 --path . res://tests/harness.tscn

const ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right",
	"leap", "swap_stance", "drum", "tail_twist", "spit", "aim", "lock_target",
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
	await check_a_near_miss_drum_rattles_the_slab()
	await check_drum_breaks_slab()
	await check_every_sound_exists()
	await check_the_glide_wind_loops()
	await check_spit_spends_a_seed()
	await check_empty_pouch_cannot_spit()
	await check_one_seed_is_one_seed()
	await check_full_pouch_refuses_pickups()
	await check_burrow_banks_the_pouch()
	await check_pod_pays_back_the_shot()
	await check_reticle_predicts_the_impact()
	await check_spit_carries_a_useful_distance()
	await check_lock_finds_a_target_and_hits_it()
	await check_locked_reticle_marks_the_target()
	await check_lock_ignores_a_spent_target()
	await check_aiming_reframes_the_camera()
	await check_gate_blocks_the_stash()
	await check_latch_drops_the_gate()
	await check_open_gate_admits_the_player()
	await check_every_mechanic_hides_a_sunseed()
	await check_every_sunseed_stands_on_ground()
	await check_lit_beacons_have_sky_above_them()
	await check_trail_gap_is_crossable()
	await check_a_parasail_landing_can_be_stopped()
	await check_toll_needs_banked_seeds()
	await check_sanctum_is_shut_before_paying()
	await check_partial_payment_persists()
	await check_part_paid_gate_cannot_be_crawled_over()
	await check_toll_opens_and_admits()
	await check_a_sunseed_survives_a_fall()
	await check_full_pouch_still_clears_gap()
	await check_full_pouch_costs_leap_height()
	await check_falling_spills_the_pouch()


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


## Must run before the slab is broken, since breaking it frees it.
func check_a_near_miss_drum_rattles_the_slab() -> void:
	var slab: Node3D = get_node_or_null("Main/CrackedSlab")
	if slab == null:
		report("a near-miss drum rattles the slab", false, "no cracked slab in the level")
		return

	var rest: float = slab.position.y
	await reset(Vector3(2, 0.4, 4), STANCE_HOP)
	await steps(10)
	var span: float = player.global_position.distance_to(slab.global_position)
	await press_tap("drum")

	var lifted := rest
	for i in 40:
		await get_tree().physics_frame
		lifted = maxf(lifted, slab.position.y)
	release_all()

	var out_of_range: bool = span > player.drum_radius and span < player.drum_notice_radius
	report(
		"a drum landing near the slab rattles it without breaking it",
		out_of_range and is_instance_valid(slab) and lifted > rest + 0.02,
		"span=%.2f lift=%.3f alive=%s" % [span, lifted - rest, is_instance_valid(slab)]
	)


## Every sound the game asks for has to be in the bank, and every buffer has to hold samples.
## A misspelt name or a synth that returns nothing is otherwise silent in every sense.
func check_every_sound_exists() -> void:
	var wanted := [
		"leap", "land", "swap", "drum", "slab_break", "slab_rattle", "wind", "spit",
		"shot_hit", "pod_burst", "pickup", "pouch_full", "deposit", "toll_tick",
		"gate_open", "sunseed", "fanfare",
	]
	var missing: Array[String] = []
	var empty: Array[String] = []
	for name in wanted:
		if not Sfx.has(name):
			missing.append(name)
			continue
		var voice := Sfx.stream(name)
		if voice.data.size() < 1000 or voice.get_length() <= 0.01:
			empty.append(name)

	report(
		"every sound is synthesised and none of them are empty",
		missing.is_empty() and empty.is_empty(),
		"count=%d missing=%s empty=%s" % [Sfx.names().size(), missing, empty]
	)


## The glide is held for seconds at a time. Wind that is not marked as looping would simply
## stop partway through, which is the sort of thing nobody notices until a playtest.
func check_the_glide_wind_loops() -> void:
	var wind := Sfx.stream("wind")
	var loops: bool = (
		wind != null
		and wind.loop_mode == AudioStreamWAV.LOOP_FORWARD
		and wind.loop_end > wind.loop_begin
	)
	report(
		"the parasail wind is a seamless loop, not a one-shot",
		loops,
		"mode=%d span=%d..%d" % [wind.loop_mode, wind.loop_begin, wind.loop_end]
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


func check_spit_spends_a_seed() -> void:
	await reset(Vector3(0, 0.4, 0), STANCE_HOP)
	GameState.pocket_seeds(4)
	var before: int = GameState.pouch
	await press_tap("spit")
	await steps(3)
	report(
		"spitting spends a pouch seed",
		GameState.pouch == before - 1,
		"pouch %d -> %d" % [before, GameState.pouch]
	)


func check_empty_pouch_cannot_spit() -> void:
	await reset(Vector3(0, 0.4, 0), STANCE_HOP)
	var before := count_shots()
	await press_tap("spit")
	await steps(3)
	report(
		"an empty pouch has nothing to spit",
		count_shots() == before,
		"%d shot(s) in flight" % (count_shots() - before)
	)


## Regression guard. Pocketing a seed emits a change signal that every seed listens to in
## order to re-offer itself, which once let a single seed keep accepting itself until the
## pouch was full. Nothing else in the suite would notice, since the other pouch checks set
## their contents by hand.
func check_one_seed_is_one_seed() -> void:
	await reset(Vector3(2.0, 0.4, -2.0), STANCE_HOP)
	var pip: Node3D = load("res://scenes/seed.tscn").instantiate()
	pip.set("bonus", true)
	pip.position = Vector3(2.0, 0.9, -2.0)
	get_node("Main").add_child(pip)
	await steps(20)
	report("one seed adds exactly one seed", GameState.pouch == 1, "pouch=%d" % GameState.pouch)


func check_full_pouch_refuses_pickups() -> void:
	await reset(Vector3(-4, 0.4, 0), STANCE_SCURRY)
	GameState.pocket_seeds(GameState.pouch_capacity)
	# A seed of our own rather than one from the level, whose fate earlier checks own.
	var pip: Node3D = load("res://scenes/seed.tscn").instantiate()
	pip.set("bonus", true)
	pip.position = Vector3(-4, 0.9, 0)
	get_node("Main").add_child(pip)
	await steps(30)
	report(
		"a full pouch leaves the seed in the world",
		is_instance_valid(pip) and GameState.pouch == GameState.pouch_capacity,
		"seed still there=%s pouch=%d" % [is_instance_valid(pip), GameState.pouch]
	)

	# Making room must re-offer it without the player having to step off and back on.
	GameState.spend_seed()
	await steps(30)
	report(
		"freeing pouch space re-offers the refused seed",
		not is_instance_valid(pip),
		"pouch=%d" % GameState.pouch
	)


func check_burrow_banks_the_pouch() -> void:
	await reset(Vector3(-10, 0.4, 10), STANCE_HOP)
	var stored_before: int = GameState.seeds_stored
	GameState.pocket_seeds(5)
	await steps(30)
	report(
		"standing on the burrow banks the whole pouch",
		GameState.pouch == 0 and GameState.seeds_stored == stored_before + 5,
		"pouch=%d stored %d -> %d" % [GameState.pouch, stored_before, GameState.seeds_stored]
	)


func check_pod_pays_back_the_shot() -> void:
	await reset(Vector3(-6, 0.4, -14), STANCE_HOP)
	GameState.pocket_seeds(2)
	var dropped_before := count_bonus_seeds()
	await aim_at(Vector3(-6, 4.6, -9.2))
	await press_tap("spit")
	await steps(120)
	var gained := count_bonus_seeds() - dropped_before
	report(
		"a spat pod drops back more seeds than the shot cost",
		gained >= 2,
		"spent 1, dropped %d" % gained
	)


## The whole reason the spit felt unaimable was that the marker on screen pointed at a place
## the seed never passed through. Prediction and reality have to be the same thing.
func check_reticle_predicts_the_impact() -> void:
	await reset(Vector3(0, 0.4, 4.0), STANCE_HOP)
	GameState.pocket_seeds(2)
	# Angled down so it strikes the plaza, which tests the prediction against a real surface
	# rather than against a shot expiring in mid-air over the void.
	await aim_along(Vector3(0.35, -0.15, -1.0).normalized())

	var predicted: Vector3 = player.predicted_impact()["position"]
	var actual := await fire_and_track()
	var error := predicted.distance_to(actual) if actual != Vector3.INF else INF
	report(
		"the reticle marks where the seed actually lands",
		error < 0.35,
		"predicted %.2v, hit %.2v, off by %.2f" % [predicted, actual, error]
	)


func check_spit_carries_a_useful_distance() -> void:
	# Down the runway, which is the only surface long enough to catch a level shot.
	await reset(Vector3(0, 0.4, -15.0), STANCE_HOP)
	GameState.pocket_seeds(2)
	await aim_along(Vector3(0.0, 0.0, -1.0))
	var muzzle: Vector3 = player.spit_muzzle()
	var actual := await fire_and_track()
	var carried := (
		Vector3(actual.x - muzzle.x, 0.0, actual.z - muzzle.z).length()
		if actual != Vector3.INF
		else 0.0
	)
	report(
		"a level spit carries a useful distance before dropping",
		carried > 15.0,
		"%.1f units" % carried
	)


func check_lock_finds_a_target_and_hits_it() -> void:
	var pod: Node3D = get_node_or_null("Main/Pods/PodLedge")
	if pod == null:
		report("a locked spit hits without manual aim", false, "no PodLedge in the level")
		return

	await reset(Vector3(0, 0.4, 30.0), STANCE_HOP)
	GameState.pocket_seeds(3)
	# Look roughly at it, badly, then let the lock do the work.
	await aim_along(Vector3(0.25, -0.1, 1.0).normalized())
	await press_tap("lock_target")
	var locked: Node3D = player.locked_target()

	var hit_node: Node3D = null
	if locked != null:
		await press_tap("spit")
		for i in 180:
			await get_tree().physics_frame
			if not pod.is_spittable():
				hit_node = pod
				break
	report(
		"lock-on acquires a pod and the spit hits it without manual aim",
		locked == pod and hit_node == pod,
		"locked=%s burst=%s" % [locked, hit_node != null]
	)


## Locking is only trustworthy if the marker agrees the shot reaches the thing you locked.
func check_locked_reticle_marks_the_target() -> void:
	var pod: Node3D = get_node_or_null("Main/Pods/PodPad")
	if pod == null:
		report("the locked reticle sits on the locked target", false, "no PodPad in the level")
		return

	# West edge of the plaza, clear of the sanctum, with an unobstructed line out to the pad.
	await reset(Vector3(-14.5, 0.4, -5.0), STANCE_HOP)
	GameState.pocket_seeds(2)
	await aim_along((pod.global_position - player.global_position).normalized())
	await press_tap("lock_target")

	var locked: Node3D = player.locked_target()
	var impact: Dictionary = player.predicted_impact()
	report(
		"the locked reticle sits on the locked target",
		locked == pod and impact["collider"] == pod,
		"locked=%s reticle hits=%s at %.2v" % [locked, impact["collider"], impact["position"]]
	)


func check_lock_ignores_a_spent_target() -> void:
	# The pod burst by the previous check is still a node, and locking onto an empty husk
	# would waste seeds on nothing.
	await reset(Vector3(0, 0.4, 30.0), STANCE_HOP)
	GameState.pocket_seeds(2)
	await aim_along(Vector3(0.0, 0.1, 1.0).normalized())
	await press_tap("lock_target")
	var locked: Node3D = player.locked_target()
	report(
		"lock-on skips a pod that has already been burst",
		locked == null or locked.is_spittable(),
		"locked=%s" % locked
	)


func check_aiming_reframes_the_camera() -> void:
	await reset(Vector3(0, 0.4, 0), STANCE_HOP)
	var rig: Node = player.get_node("CamPivot")
	var arm: SpringArm3D = rig.get_node("SpringArm3D")
	var resting: float = arm.spring_length
	Input.action_press("aim")
	await steps(40)
	var aimed: float = arm.spring_length
	var shoulder: float = arm.position.x
	var aiming: bool = rig.aiming
	release_all()
	await steps(40)
	report(
		"holding aim pulls the camera in over the shoulder",
		aiming and aimed < resting - 1.0 and shoulder > 0.4,
		"arm %.2f -> %.2f, shoulder %.2f" % [resting, aimed, shoulder]
	)


## Must run before the latch check, which opens the gate for good.
func check_gate_blocks_the_stash() -> void:
	await reset(Vector3(6.0, 0.4, -9.0), STANCE_SCURRY)
	Input.action_press("move_right")
	await steps(120)
	var x: float = player.global_position.x
	release_all()
	report("the closed gate keeps you out of the stash", x < 9.1, "stopped at x=%.2f" % x)


func check_latch_drops_the_gate() -> void:
	var gate: Node3D = get_node_or_null("Main/StashGate")
	if gate == null:
		report("spitting the latch drops the stash gate", false, "no StashGate in the level")
		return
	await reset(Vector3(0, 0.4, -9), STANCE_HOP)
	GameState.pocket_seeds(2)
	var before: float = gate.position.y
	await aim_at(Vector3(8.87, 2.5, -9))
	await press_tap("spit")
	await steps(150)
	report(
		"spitting the latch drops the stash gate",
		gate.position.y < before - 1.5,
		"gate y %.2f -> %.2f" % [before, gate.position.y]
	)


## Proving the gate moved is not the same as proving it granted anything.
func check_open_gate_admits_the_player() -> void:
	await reset(Vector3(6.0, 0.4, -9.0), STANCE_SCURRY)
	Input.action_press("move_right")
	await steps(150)
	var x: float = player.global_position.x
	var picked: int = GameState.pouch
	release_all()
	report(
		"the opened gate admits you to the stashed seeds",
		x > 10.5 and picked > 0,
		"reached x=%.2f with %d seed(s)" % [x, picked]
	)


## Stood on the toll, just outside the sanctum doorway.
const TOLL_STAND := Vector3(-6.1, 0.4, -10.0)


func warden() -> Node:
	return get_node_or_null("Main/WardenGate")


func check_every_mechanic_hides_a_sunseed() -> void:
	report(
		"every mechanic hides a sunseed",
		GameState.sunseeds_total == 6,
		"%d registered" % GameState.sunseeds_total
	)


## A sunseed hanging over the void would be counted but unreachable, which reads to a player
## as a miscount rather than as a missing platform.
func check_every_sunseed_stands_on_ground() -> void:
	var space := player.get_world_3d().direct_space_state
	var stranded: Array[String] = []
	for node in get_node("Main/Sunseeds").get_children():
		var seed_node := node as Node3D
		var from: Vector3 = seed_node.global_position + Vector3.UP * 0.2
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0)
		query.collision_mask = 1
		if space.intersect_ray(query).is_empty():
			stranded.append(seed_node.name)
	report(
		"every sunseed sits on ground you can stand on",
		stranded.is_empty(),
		"stranded: %s" % ("none" if stranded.is_empty() else ", ".join(stranded))
	)


## A beacon under a roof is worse than no beacon: it is invisible from outside and it puts a
## column of light inside the ceiling. This catches a sunseed left lit that should not be, and
## would catch roofing something over an existing one later.
func check_lit_beacons_have_sky_above_them() -> void:
	var space := player.get_world_3d().direct_space_state
	var buried: Array[String] = []
	for node in get_node("Main/Sunseeds").get_children():
		if not node.beacon:
			continue
		var from: Vector3 = node.global_position + Vector3.UP * 0.6
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 14.0)
		query.collision_mask = 1
		if not space.intersect_ray(query).is_empty():
			buried.append(node.name)
	report(
		"every lit beacon has open sky above it",
		buried.is_empty(),
		"buried: %s" % ("none" if buried.is_empty() else ", ".join(buried))
	)


## The runway's 13-unit gap had no coverage at all, which makes it the prime suspect for a
## sunseed that can be counted but never collected.
func check_trail_gap_is_crossable() -> void:
	await reset(Vector3(0, 0.4, -30.0), STANCE_SCURRY)
	Input.action_press("move_forward")
	for i in 600:
		await get_tree().physics_frame
		if player.global_position.z <= -67.0:
			break
	var ran_at: float = player.horizontal_speed()
	await press_tap("swap_stance")
	await press_tap("leap")
	var result := await settle(400)
	release_all()
	report(
		"a converted leap crosses the runway's trail gap",
		result.pos.z < -83.0 and result.pos.y > -1.0,
		"ran %.1f, landed z=%.2f y=%.2f" % [ran_at, result.pos.z, result.pos.y]
	)


## Regression for the icy landing: above the stance cap, releasing the stick used to apply no
## friction at all, so a glide landing slid on until it ran out of ledge.
func check_a_parasail_landing_can_be_stopped() -> void:
	await reset(Vector3(0, 0.4, 0), STANCE_HOP)
	# Drop in already gliding at full parasail speed, then ask for nothing at all.
	player.global_position = Vector3(0, 3.0, 0)
	player.velocity = Vector3(0, 0, -player.parasail_forward)
	player.state = 5
	await steps(10)
	release_all()

	var stopped_in := -1
	for i in 90:
		await get_tree().physics_frame
		if player.is_on_floor() and player.horizontal_speed() < 0.5:
			stopped_in = i
			break
	report(
		"a glide landing stops when you let go",
		stopped_in >= 0,
		"halted after %d frames at %.2f u/s" % [stopped_in, player.horizontal_speed()]
	)


func check_toll_needs_banked_seeds() -> void:
	var gate := warden()
	if gate == null:
		report("the toll takes nothing when nothing is banked", false, "no WardenGate")
		return

	await reset(TOLL_STAND, STANCE_HOP)
	set_stored(0)
	await steps(90)
	report(
		"the toll takes nothing when nothing is banked",
		not gate.is_open() and gate.paid() == 0,
		"paid %d/%d open=%s" % [gate.paid(), gate.cost, gate.is_open()]
	)


func check_sanctum_is_shut_before_paying() -> void:
	await reset(TOLL_STAND, STANCE_SCURRY)
	set_stored(0)
	Input.action_press("move_left")
	await steps(120)
	var x: float = player.global_position.x
	release_all()
	report(
		"the sanctum is shut until the toll is paid",
		x > -8.3,
		"stopped at x=%.2f" % x
	)


## An interrupted payment has to be worth something, or a toll larger than one burrow trip
## would be impossible to chip away at.
func check_partial_payment_persists() -> void:
	var gate := warden()
	await reset(TOLL_STAND, STANCE_HOP)
	set_stored(8)
	await steps(90)
	var paid_before: int = gate.paid()
	var left_over: int = GameState.seeds_stored

	# Walk off the toll entirely, then come back and confirm nothing was refunded or lost.
	await reset(Vector3(0, 0.4, 0), STANCE_HOP)
	await steps(30)
	await reset(TOLL_STAND, STANCE_HOP)
	await steps(30)

	report(
		"a part-paid toll keeps what it has already been given",
		paid_before == 8 and left_over == 0 and gate.paid() == 8 and not gate.is_open(),
		"paid %d/%d, %d still banked" % [gate.paid(), gate.cost, GameState.seeds_stored]
	)


## Regression: the barrier used to sink in proportion to payment, which opened a crawlable
## gap long before the toll was settled. Scurrying is the shortest the creature ever gets, so
## it is the shape that would slip through.
func check_part_paid_gate_cannot_be_crawled_over() -> void:
	var gate := warden()
	if gate == null or gate.is_open():
		report("a part-paid gate cannot be crawled over", false, "gate missing or already open")
		return

	await reset(TOLL_STAND, STANCE_SCURRY)
	Input.action_press("move_left")
	await steps(150)
	var x: float = player.global_position.x
	release_all()
	report(
		"a part-paid gate cannot be crawled over",
		x > -8.3 and not gate.is_open(),
		"paid %d/%d, scurried to x=%.2f" % [gate.paid(), gate.cost, x]
	)


func check_toll_opens_and_admits() -> void:
	var gate := warden()
	await reset(TOLL_STAND, STANCE_HOP)
	# Twelve short of the twenty, on top of the eight already handed over.
	set_stored(12)
	await steps(140)
	var opened: bool = gate.is_open()
	var spent_all: bool = GameState.seeds_stored == 0

	var found_before: int = GameState.sunseeds_found
	Input.action_press("move_left")
	await steps(150)
	release_all()

	report(
		"paying the toll opens the sanctum and its sunseed",
		opened and spent_all and GameState.sunseeds_found == found_before + 1,
		"open=%s banked=%d sunseeds %d -> %d at x=%.2f" % [
			opened,
			GameState.seeds_stored,
			found_before,
			GameState.sunseeds_found,
			player.global_position.x,
		]
	)


## Seeds scatter when you go down. Progress must not, or every run would be a gamble on the
## last leap rather than on the next one.
func check_a_sunseed_survives_a_fall() -> void:
	var before: int = GameState.sunseeds_found
	if before <= 0:
		report("a gathered sunseed survives a fall", false, "nothing gathered yet to lose")
		return

	await reset(Vector3(0, 0.4, 0), STANCE_HOP)
	GameState.pocket_seeds(8)
	player.global_position = Vector3(0, -40, 0)
	await steps(90)
	report(
		"a gathered sunseed survives a fall",
		GameState.sunseeds_found == before,
		"%d before, %d after (pouch %d)" % [before, GameState.sunseeds_found, GameState.pouch]
	)


## Test-only: put the banked pool at a known figure. Checks bank real seeds at the burrow,
## so without this a toll test would inherit whatever the previous one happened to leave.
func set_stored(count: int) -> void:
	GameState.spend_stored(GameState.seeds_stored)
	if count > 0:
		GameState.seeds_stored = count
		GameState.stored_changed.emit(count)


func check_full_pouch_still_clears_gap() -> void:
	# The gap is dimensioned for an empty pouch. Carrying a full load must cost distance
	# without silently turning the level's centrepiece into a coin flip.
	await reset(Vector3(0, 0.4, 14.0), STANCE_SCURRY)
	GameState.pocket_seeds(GameState.pouch_capacity)
	Input.action_press("move_back")
	await run_until_z(TAKEOFF_Z)
	await press_tap("swap_stance")
	await press_tap("leap")
	var result := await settle(300)
	release_all()
	report(
		"a converted leap still clears the gap with full cheeks",
		result.on_ledge,
		"pouch=%d landed z=%.2f y=%.2f" % [GameState.pouch, result.pos.z, result.pos.y]
	)


## The gap check above proves a full load still clears, which on its own would also be true
## if the weight penalty did nothing at all. Measure the apex directly so the cost is known
## to exist and known to be small.
func check_full_pouch_costs_leap_height() -> void:
	var empty := await vertical_leap(Vector3(-15.5, 0.4, 0), 0.75)
	await reset(Vector3(-15.5, 0.4, 0), STANCE_HOP)
	GameState.pocket_seeds(GameState.pouch_capacity)
	var full := await loaded_vertical_leap(Vector3(-15.5, 0.4, 0), 0.75)
	var loss := empty - full
	report(
		"full cheeks cost leap height, but only a little",
		loss > 0.2 and loss < 0.9,
		"apex %.2f empty, %.2f full (-%.2f)" % [empty, full, loss]
	)


func check_falling_spills_the_pouch() -> void:
	await reset(Vector3(0, 0.4, 24), STANCE_HOP)
	var carried := GameState.pocket_seeds(8)
	var saved: float = player.kill_y
	player.kill_y = -14.0
	player.global_position = Vector3(0, -4.0, 39.0)
	for i in 300:
		await get_tree().physics_frame
		if GameState.pouch < carried:
			break
	player.kill_y = saved
	report(
		"falling out of the level scatters half the load",
		GameState.pouch == carried / 2,
		"carried %d, kept %d" % [carried, GameState.pouch]
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
	return await loaded_vertical_leap(from, charge_seconds)


## Same measurement without the reset, for checks that need to set up a pouch first (reset
## deliberately empties it).
func loaded_vertical_leap(_from: Vector3, charge_seconds: float) -> float:
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


## Point the rig so a spit passes through a world position, using the same solver the game
## uses rather than a second copy that could drift away from it.
func aim_at(target: Vector3) -> void:
	var muzzle: Vector3 = player.get_node("Body/Head/Snout").global_position
	var dir := Ballistics.direction_to(muzzle, target, player.spit_speed, player.spit_gravity)
	await aim_along(dir)


func aim_along(dir: Vector3) -> void:
	var rig: Node = player.get_node("CamPivot")
	var flat := Vector3(dir.x, 0.0, dir.z)
	rig.set("_yaw", atan2(-dir.x, -dir.z))
	rig.set("_pitch", atan2(dir.y, flat.length()))
	await get_tree().physics_frame


## Fire one seed and report where it came down, or INF if it never reported an impact.
## The result travels out through an Array because GDScript lambdas capture by value, so
## assigning to a captured local would only ever update the lambda's own copy.
func fire_and_track() -> Vector3:
	# The previous check's shot can still be fading out in the group, and it has already
	# emitted its impact, so grabbing the first entry can mean waiting forever on a spent one.
	var existing := get_tree().get_nodes_in_group("seed_shot")
	await press_tap("spit")

	var shot: SeedShot = null
	for node in get_tree().get_nodes_in_group("seed_shot"):
		if node not in existing:
			shot = node
			break
	if shot == null:
		return Vector3.INF

	var landed: Array[Vector3] = []
	shot.impacted.connect(func(point: Vector3, _collider: Node3D) -> void: landed.append(point))
	for i in 300:
		await get_tree().physics_frame
		if not landed.is_empty():
			return landed[0]
	return Vector3.INF


func count_shots() -> int:
	return get_tree().get_nodes_in_group("seed_shot").size()


func count_bonus_seeds() -> int:
	var total := 0
	for node in get_tree().get_nodes_in_group("seed"):
		if node.get("bonus"):
			total += 1
	return total


func reset(pos: Vector3, stance: int) -> void:
	release_all()
	# Carried seeds add weight, so leaving them between checks would let one measurement
	# quietly change the next one.
	GameState.clear_pouch()
	# Same reasoning for the rig: aiming a spit rotates it, and movement input is expressed
	# relative to it, so a stale yaw silently redefines which way "forward" means.
	var rig: Node = player.get_node("CamPivot")
	rig.set("_yaw", 0.0)
	rig.set("_pitch", 0.0)
	# A cooldown or a lock left over from the previous check would silently swallow the next
	# shot, which reads as a broken mechanic rather than as a dirty fixture.
	player._spit_timer = 0.0
	player._locked = null
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
