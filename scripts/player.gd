extends CharacterBody3D

## Dual-stance controller for a jerboa / elephant-shrew / kangaroo-rat hybrid.
##
## Scurry (quadrupedal) owns horizontal speed and has almost no vertical.
## Hop (bipedal) is sluggish on the ground but owns the leap, the parasail and the drum.
##
## The mechanic the prototype exists to test is the conversion: swapping out of a fast
## scurry banks that speed, and a leap taken before the window closes launches at the
## banked speed instead of the hop stance cap. Banked speed is held flat for the whole
## window rather than bleeding away, so a full-length charge still launches converted.

signal stance_changed(new_stance: int)
signal momentum_banked(speed: float)
signal drummed(origin: Vector3)
signal spat(origin: Vector3, direction: Vector3)

enum Stance { SCURRY, HOP }
enum State {
	SCURRY_GROUND,
	SCURRY_AIR,
	HOP_GROUND,
	HOP_CROUCH,
	HOP_AIR,
	HOP_PARASAIL,
	HOP_DRUM,
}

const HOP_SHAPE_HEIGHT := 1.4
const HOP_SHAPE_RADIUS := 0.30
const SCURRY_SHAPE_HEIGHT := 0.60
const SCURRY_SHAPE_RADIUS := 0.26

@export_group("Scurry")
@export var scurry_speed := 11.0
@export var scurry_accel := 60.0
@export var scurry_friction := 40.0
@export var scurry_turn_speed := 14.0
@export var scurry_hop_height := 1.0
@export var trail_boost := 1.35

@export_group("Hop")
@export var hop_stance_speed := 4.5
@export var hop_accel := 25.0
@export var hop_friction := 30.0
@export var hop_turn_speed := 9.0
@export var hop_tap_height := 1.2
@export var hop_max_height := 5.0
@export var charge_time := 0.6

@export_group("Conversion")
## Fraction of scurry speed banked as leap power when swapping stance.
@export var momentum_conversion := 0.7
## How long banked speed stays usable. Must exceed charge_time or a full charge
## can never launch converted.
@export var momentum_window := 1.0
## How fast speed above the current stance cap bleeds off. Kept gentle so a fast
## landing swapped into scurry reads as a burst rather than a wall.
@export var overspeed_decay := 3.0
@export var overspeed_steer := 3.0

@export_group("Air")
@export var gravity := 22.0
@export var air_accel := 9.0
## The twist redirects existing speed rather than adding to it, so it stays a rudder
## instead of becoming a free distance boost that trivialises every gap.
@export var tail_twist_speed := 6.0
@export var leap_buffer := 0.15

@export_group("Parasail")
## Glide ratio (forward / fall) is deliberately kept near 1.3. Anything much higher and
## the parasail covers more ground than a converted leap, which would make the whole
## conversion mechanic pointless.
@export var parasail_fall_speed := 4.5
@export var parasail_forward := 6.0
@export var parasail_turn_speed := 3.0
@export var parasail_settle := 12.0

@export_group("Drum")
@export var drum_rise := 3.0
@export var drum_rise_time := 0.16
@export var drum_fall_speed := 30.0
@export var drum_radius := 4.0
## Drums landing between drum_radius and this still rattle a breakable, so a near miss shows
## you the connection instead of being indistinguishable from drumming on bare sand.
@export var drum_notice_radius := 11.0

@export_group("Spit")
@export var spit_scene: PackedScene
@export var spit_cooldown := 0.32
## Pushed clear of the snout so the shot does not spawn inside the player's own head.
@export var spit_muzzle_offset := 0.22
## The arc lives here rather than on the projectile, because the reticle and the lock-on
## have to predict with exactly the numbers the shot will fly with.
@export var spit_speed := 30.0
@export var spit_gravity := 6.0

@export_group("Lock-on")
@export var lock_range := 45.0
## How far off the centre of view a target may sit, as a dot product against the aim.
@export var lock_cone := 0.45

@export_group("Pouch")
## Full cheeks make you heavier off the ground. Deliberately small: the conversion gap is
## dimensioned for an empty pouch, and a large penalty would make the level's gating look
## broken rather than reading as a cost you chose to carry.
@export var pouch_weight_penalty := 0.1
## Fraction of the load scattered by falling out of the level.
@export var pouch_loss_on_fall := 0.5

@export_group("Pose")
@export var pose_speed := 12.0
@export var facing_speed := 18.0
@export var crouch_dip := 0.22
@export var cheek_max_scale := 2.2
@export var spit_kick_deg := 18.0

## Per-part poses. Rotating the whole rig to go quadrupedal just face-plants the creature:
## the head ends up buried and the tail points at the sky. Each part has to be placed.
const POSE_HOP := {
	"Torso": {"pos": Vector3(0, 0.6, 0.02), "rot": Vector3(0, 0, 0), "scale": Vector3(1, 1, 1)},
	"Head": {"pos": Vector3(0, 1.02, -0.03), "rot": Vector3(0, 0, 0), "scale": Vector3(1, 1, 1)},
	"Tail": {"pos": Vector3(0, 0.52, 0.19), "rot": Vector3(115, 0, 0), "scale": Vector3(1, 1, 1)},
	"ThighL": {"pos": Vector3(-0.14, 0.2, 0.04), "rot": Vector3(0, 0, 0), "scale": Vector3(1, 1, 1)},
	"ThighR": {"pos": Vector3(0.14, 0.2, 0.04), "rot": Vector3(0, 0, 0), "scale": Vector3(1, 1, 1)},
	"FootL": {"pos": Vector3(-0.14, 0.026, -0.05), "rot": Vector3(0, 0, 0), "scale": Vector3(1, 1, 1)},
	"FootR": {"pos": Vector3(0.14, 0.026, -0.05), "rot": Vector3(0, 0, 0), "scale": Vector3(1, 1, 1)},
	"ForelegL": {"pos": Vector3(-0.15, 0.6, -0.16), "rot": Vector3(24, 0, 0), "scale": Vector3(1, 1, 1)},
	"ForelegR": {"pos": Vector3(0.15, 0.6, -0.16), "rot": Vector3(24, 0, 0), "scale": Vector3(1, 1, 1)},
}

const POSE_SCURRY := {
	"Torso": {"pos": Vector3(0, 0.36, 0.04), "rot": Vector3(90, 0, 0), "scale": Vector3(1, 1, 1)},
	"Head": {"pos": Vector3(0, 0.4, -0.44), "rot": Vector3(12, 0, 0), "scale": Vector3(1, 1, 1)},
	"Tail": {"pos": Vector3(0, 0.4, 0.36), "rot": Vector3(76, 0, 0), "scale": Vector3(1, 1, 1)},
	"ThighL": {"pos": Vector3(-0.16, 0.18, 0.2), "rot": Vector3(0, 0, 0), "scale": Vector3(1, 1, 1)},
	"ThighR": {"pos": Vector3(0.16, 0.18, 0.2), "rot": Vector3(0, 0, 0), "scale": Vector3(1, 1, 1)},
	"FootL": {"pos": Vector3(-0.16, 0.026, 0.12), "rot": Vector3(0, 0, 0), "scale": Vector3(1, 1, 1)},
	"FootR": {"pos": Vector3(0.16, 0.026, 0.12), "rot": Vector3(0, 0, 0), "scale": Vector3(1, 1, 1)},
	"ForelegL": {"pos": Vector3(-0.13, 0.17, -0.3), "rot": Vector3(0, 0, 0), "scale": Vector3(1, 1.9, 1)},
	"ForelegR": {"pos": Vector3(0.13, 0.17, -0.3), "rot": Vector3(0, 0, 0), "scale": Vector3(1, 1.9, 1)},
}

const EAR_HOP := Vector3(0, 0, 10)
const EAR_SCURRY := Vector3(48, 0, 16)
const EAR_PARASAIL := Vector3(-6, 0, 66)

@export_group("World")
@export var kill_y := -30.0

var stance: int = Stance.HOP
var state: int = State.HOP_GROUND
var facing := Vector3.FORWARD
var on_trail := false

var charge := 0.0
var momentum_speed := 0.0
var momentum_timer := 0.0
## Banking momentum also pre-charges the leap, so the conversion is a quick swap-then-tap
## flick rather than a long hold that skids you off the edge you were aiming for.
var momentum_charge := 0.0
var twist_used := false

var _buffered_leap := 0.0
var _drum_rise_timer := 0.0
var _spawn_transform: Transform3D
var _cheek_scale := 1.0
var _spit_timer := 0.0
var _spit_kick := 0.0
var _locked: Node3D = null
## Fastest descent of the current airtime, so a landing can be voiced as hard as it was.
var _air_fall := 0.0

@onready var collision: CollisionShape3D = $Collision
@onready var head_room: ShapeCast3D = $HeadRoom
@onready var body: Node3D = $Body
@onready var ear_l: Node3D = $Body/Head/EarL
@onready var ear_r: Node3D = $Body/Head/EarR
@onready var cheek_l: Node3D = $Body/Head/CheekL
@onready var cheek_r: Node3D = $Body/Head/CheekR
@onready var snout: Node3D = $Body/Head/Snout
@onready var cam_pivot: Node3D = $CamPivot


func _ready() -> void:
	_spawn_transform = global_transform
	# The shape is a SubResource so it is already local to this scene, but duplicating
	# keeps stance resizing safe if the player is ever instanced more than once.
	collision.shape = collision.shape.duplicate()
	head_room.add_exception(self)
	_apply_stance(Stance.HOP)
	GameState.pouch_changed.connect(_on_pouch_changed)
	_on_pouch_changed(GameState.pouch, GameState.pouch_capacity)


func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	if Input.is_action_just_pressed("respawn"):
		_respawn()
		return
	if Input.is_action_just_pressed("leap"):
		_buffered_leap = leap_buffer
	if Input.is_action_just_pressed("swap_stance"):
		_swap_stance()
	# Spitting works in both stances. It is a cheek action rather than a leg action, so
	# gating it on stance would be arbitrary, and it gives scurry its only verb besides
	# running fast.
	if Input.is_action_just_pressed("spit") and state != State.HOP_DRUM:
		_try_spit()
	if Input.is_action_just_pressed("lock_target"):
		_toggle_lock()
	_validate_lock()

	var input_dir := _input_direction()

	match state:
		State.SCURRY_GROUND:
			_scurry_ground(delta, input_dir)
		State.SCURRY_AIR:
			_scurry_air(delta, input_dir)
		State.HOP_GROUND:
			_hop_ground(delta, input_dir)
		State.HOP_CROUCH:
			_hop_crouch(delta, input_dir)
		State.HOP_AIR:
			_hop_air(delta, input_dir)
		State.HOP_PARASAIL:
			_hop_parasail(delta, input_dir)
		State.HOP_DRUM:
			_hop_drum(delta)

	# Sampled before the move, since move_and_slide() is what cancels the fall against the
	# floor, and after the handlers, so the landing they queued still sees the old value.
	_air_fall = 0.0 if is_on_floor() else maxf(_air_fall, -velocity.y)

	var gliding := state == State.HOP_PARASAIL
	Sfx.set_wind(_horizontal().length() / maxf(parasail_forward, 0.01) if gliding else 0.0)

	move_and_slide()
	_update_pose(delta)

	if global_position.y < kill_y:
		_fall_out()


# --- states ------------------------------------------------------------------


func _scurry_ground(delta: float, input_dir: Vector3) -> void:
	var cap := scurry_speed * (trail_boost if on_trail else 1.0)
	_ground_move(delta, input_dir, cap, scurry_accel, scurry_friction, scurry_turn_speed)
	if _consume_leap():
		velocity.y = _launch_speed_for(scurry_hop_height)
		# Higher and thinner than the bipedal launch, so the two hops never sound alike.
		Sfx.play("leap", -14.0, 1.45)
		_set_state(State.SCURRY_AIR)
	elif not is_on_floor():
		_set_state(State.SCURRY_AIR)


func _scurry_air(delta: float, input_dir: Vector3) -> void:
	velocity.y -= gravity * delta
	_air_steer(delta, input_dir, scurry_speed * (trail_boost if on_trail else 1.0))
	if is_on_floor():
		_set_state(State.SCURRY_GROUND)


func _hop_ground(delta: float, input_dir: Vector3) -> void:
	var cap := maxf(hop_stance_speed, momentum_speed)
	_ground_move(delta, input_dir, cap, hop_accel, hop_friction, hop_turn_speed)

	if Input.is_action_just_pressed("drum"):
		_do_drum()
		return
	if _buffered_leap > 0.0 or Input.is_action_pressed("leap"):
		_buffered_leap = 0.0
		charge = 0.0
		_set_state(State.HOP_CROUCH)
	elif not is_on_floor():
		_set_state(State.HOP_AIR)


func _hop_crouch(delta: float, input_dir: Vector3) -> void:
	charge = minf(charge + delta, charge_time)
	# Compressing commits you: you keep the speed you came in with but steer poorly.
	var cap := maxf(hop_stance_speed, momentum_speed)
	_ground_move(delta, input_dir, cap, hop_accel * 0.3, hop_friction * 0.25, hop_turn_speed * 0.35)

	if not Input.is_action_pressed("leap"):
		_launch(input_dir)
	elif not is_on_floor():
		_set_state(State.HOP_AIR)


func _hop_air(delta: float, input_dir: Vector3) -> void:
	velocity.y -= gravity * delta
	_air_steer(delta, input_dir, maxf(hop_stance_speed, _horizontal().length()))
	_try_twist(input_dir)

	if Input.is_action_just_pressed("drum"):
		_start_drum()
		return
	# Parasail only past the apex, so it extends a leap instead of replacing it.
	if velocity.y <= 0.0 and Input.is_action_pressed("leap"):
		_set_state(State.HOP_PARASAIL)
		return
	if is_on_floor():
		_land_hop()


func _hop_parasail(delta: float, input_dir: Vector3) -> void:
	velocity.y = move_toward(velocity.y, -parasail_fall_speed, gravity * delta)

	if input_dir.length() > 0.1:
		facing = _turn_toward(facing, input_dir, parasail_turn_speed * delta)
	var speed := move_toward(_horizontal().length(), parasail_forward, parasail_settle * delta)
	_set_horizontal(facing * speed)

	_try_twist(input_dir)

	if Input.is_action_just_pressed("drum"):
		_start_drum()
		return
	if not Input.is_action_pressed("leap"):
		_set_state(State.HOP_AIR)
		return
	if is_on_floor():
		_land_hop()


func _hop_drum(delta: float) -> void:
	if _drum_rise_timer > 0.0:
		_drum_rise_timer -= delta
		velocity.y = drum_rise
		_set_horizontal(_horizontal().move_toward(Vector3.ZERO, 30.0 * delta))
		return

	velocity.y = -drum_fall_speed
	_set_horizontal(_horizontal().move_toward(Vector3.ZERO, 60.0 * delta))
	if is_on_floor():
		_do_drum()
		_set_state(State.HOP_GROUND)


# --- stance ------------------------------------------------------------------


func _swap_stance() -> void:
	if stance == Stance.SCURRY:
		if not _has_headroom():
			return
		var speed := _horizontal().length()
		if speed > hop_stance_speed:
			momentum_speed = speed * momentum_conversion
			momentum_timer = momentum_window
			momentum_charge = 1.0
			momentum_banked.emit(momentum_speed)
		_apply_stance(Stance.HOP)
		_set_state(State.HOP_GROUND if is_on_floor() else State.HOP_AIR)
	else:
		# Landing fast and swapping down converts the arrival into a run: horizontal
		# speed is kept and bleeds toward the scurry cap instead of being clamped.
		momentum_speed = 0.0
		momentum_timer = 0.0
		momentum_charge = 0.0
		_apply_stance(Stance.SCURRY)
		_set_state(State.SCURRY_GROUND if is_on_floor() else State.SCURRY_AIR)
	charge = 0.0
	_drum_rise_timer = 0.0
	# Rising into the tall stance, falling into the low one, so the swap tells you which way
	# you went without looking at the readout.
	Sfx.play("swap", -15.0, 1.22 if stance == Stance.HOP else 0.86)


func _apply_stance(new_stance: int) -> void:
	stance = new_stance
	var shape := collision.shape as CapsuleShape3D
	if stance == Stance.HOP:
		shape.height = HOP_SHAPE_HEIGHT
		shape.radius = HOP_SHAPE_RADIUS
		collision.position.y = HOP_SHAPE_HEIGHT * 0.5
	else:
		shape.height = SCURRY_SHAPE_HEIGHT
		shape.radius = SCURRY_SHAPE_RADIUS
		collision.position.y = SCURRY_SHAPE_HEIGHT * 0.5
	stance_changed.emit(stance)


func _has_headroom() -> bool:
	head_room.force_shapecast_update()
	return not head_room.is_colliding()


# --- actions -----------------------------------------------------------------


func _launch(input_dir: Vector3) -> void:
	var t := maxf(charge / maxf(charge_time, 0.001), momentum_charge)
	velocity.y = _launch_speed_for(lerpf(hop_tap_height, hop_max_height, t) * _pouch_weight())
	# Charge is otherwise invisible at the moment it is spent: the meter empties as you leave
	# the ground. Dropping the pitch as the leap grows lets you hear what you paid for.
	Sfx.play("leap", lerpf(-13.0, -4.0, t), lerpf(1.24, 0.8, t))

	var current := _horizontal()
	var carry := maxf(current.length(), momentum_speed)
	if carry > 0.05:
		var dir := facing
		if input_dir.length() > 0.1:
			dir = input_dir.normalized()
		elif current.length() > 0.1:
			dir = current.normalized()
		_set_horizontal(dir * carry)

	charge = 0.0
	momentum_speed = 0.0
	momentum_timer = 0.0
	momentum_charge = 0.0
	twist_used = false
	_set_state(State.HOP_AIR)


## Spend a cheek seed to fire one along the current aim. Aimed rather than fired straight
## ahead, because the pods worth shooting are hung where you cannot walk.
func _try_spit() -> void:
	if _spit_timer > 0.0 or spit_scene == null:
		return
	if not GameState.spend_seed():
		return
	_spit_timer = spit_cooldown

	var dir := spit_aim_direction()
	var origin := spit_muzzle()
	var shot: SeedShot = spit_scene.instantiate()
	shot.speed = spit_speed
	shot.shot_gravity = spit_gravity
	get_parent().add_child(shot)
	shot.launch(origin, dir, get_rid())

	# Snap to face the shot so the recoil and the projectile agree with each other.
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.01:
		facing = flat.normalized()
	_spit_kick = 1.0
	cam_pivot.kick()
	Sfx.play("spit", -10.0, randf_range(0.94, 1.08))
	spat.emit(origin, dir)


func spit_muzzle() -> Vector3:
	return snout.global_position + spit_aim_direction() * spit_muzzle_offset


## A locked target overrides where you are looking and solves its own arc. Free aim is the
## expressive option; the lock exists for when the camera is fighting you.
func spit_aim_direction() -> Vector3:
	if _locked != null and is_instance_valid(_locked):
		return Ballistics.direction_to(
			snout.global_position, _locked.global_position, spit_speed, spit_gravity
		)
	return cam_pivot.aim_direction()


## Where the next shot would actually land. The reticle draws here, and the harness checks
## it against a real shot, so the marker cannot quietly start lying again.
func predicted_impact() -> Dictionary:
	return Ballistics.trace(
		get_world_3d(),
		spit_muzzle(),
		spit_aim_direction(),
		spit_speed,
		spit_gravity,
		[get_rid()]
	)


func locked_target() -> Node3D:
	return _locked if _locked != null and is_instance_valid(_locked) else null


func is_aiming() -> bool:
	return cam_pivot.aiming


func _toggle_lock() -> void:
	if locked_target() != null:
		_locked = null
		return
	_locked = _find_lock_target()


func _find_lock_target() -> Node3D:
	var origin: Vector3 = snout.global_position
	var forward: Vector3 = cam_pivot.aim_direction()
	var best: Node3D = null
	var best_score := -INF

	for node in get_tree().get_nodes_in_group("spittable"):
		var target := node as Node3D
		if not _is_lockable(target):
			continue
		var offset := target.global_position - origin
		var distance := offset.length()
		if distance > lock_range or distance < 0.1:
			continue
		var alignment := (offset / distance).dot(forward)
		if alignment < lock_cone:
			continue
		if not _can_reach(target):
			continue
		# Centre of view dominates, with nearer targets breaking ties.
		var score := alignment - distance / lock_range * 0.3
		if score > best_score:
			best_score = score
			best = target

	return best


func _is_lockable(target: Node3D) -> bool:
	if target == null or not target.is_inside_tree():
		return false
	# A burst pod or a thrown latch is still a node, but it is no longer worth a seed.
	if target.has_method("is_spittable"):
		return target.is_spittable()
	return true


## Whether the solved arc actually connects, rather than whether a straight line does. The
## seed travels a curve, so a target with clear line of sight can still be unreachable, and
## locking onto one would promise a hit the shot cannot deliver.
func _can_reach(target: Node3D) -> bool:
	var origin: Vector3 = snout.global_position
	var dir := Ballistics.direction_to(origin, target.global_position, spit_speed, spit_gravity)
	var result := Ballistics.trace(
		get_world_3d(), origin + dir * spit_muzzle_offset, dir, spit_speed, spit_gravity, [get_rid()]
	)
	return result["collider"] == target


func _validate_lock() -> void:
	if _locked == null:
		return
	if not _is_lockable(_locked):
		_locked = null
		return
	if snout.global_position.distance_to(_locked.global_position) > lock_range:
		_locked = null


func _pouch_weight() -> float:
	return 1.0 - pouch_weight_penalty * GameState.pouch_ratio()


func _try_twist(input_dir: Vector3) -> void:
	if twist_used or not Input.is_action_just_pressed("tail_twist"):
		return
	twist_used = true
	var dir := input_dir.normalized() if input_dir.length() > 0.1 else facing
	_set_horizontal(dir * maxf(_horizontal().length(), tail_twist_speed))
	facing = dir


func _start_drum() -> void:
	_drum_rise_timer = drum_rise_time
	_set_state(State.HOP_DRUM)


func _do_drum() -> void:
	drummed.emit(global_position)
	Sfx.play("drum", -4.0)
	for node in get_tree().get_nodes_in_group("drummable"):
		var target := node as Node3D
		if target == null:
			continue
		var distance := target.global_position.distance_to(global_position)
		if distance <= drum_radius:
			if target.has_method("on_drum"):
				target.on_drum(global_position)
		elif distance <= drum_notice_radius and target.has_method("on_drum_nearby"):
			target.on_drum_nearby(global_position)


func _land_hop() -> void:
	twist_used = false
	_set_state(State.HOP_GROUND)


# --- movement helpers --------------------------------------------------------


func _ground_move(
	delta: float,
	input_dir: Vector3,
	cap: float,
	accel: float,
	friction: float,
	turn_speed: float
) -> void:
	_accelerate(delta, input_dir, cap, accel, friction)
	if input_dir.length() > 0.05:
		facing = _turn_toward(facing, input_dir, turn_speed * delta)
	# Small downward bias so slopes stay attached through move_and_slide.
	velocity.y = -1.0


func _accelerate(delta: float, dir: Vector3, cap: float, accel: float, friction: float) -> void:
	var h := _horizontal()
	var speed := h.length()

	if speed > cap + 0.01:
		var new_dir := h / speed
		# Letting go of the stick has to brake, even above the cap. Overspeed used to ignore
		# friction entirely, so a parasail landing at 6.0 against a 4.5 cap kept sliding for
		# half a second no matter what you did, which reads as ice and walks you off ledges.
		# Carrying speed is still the reward for holding a direction, just no longer the
		# punishment for releasing one.
		if dir.length() <= 0.05:
			_set_horizontal(new_dir * move_toward(speed, cap, friction * delta))
			return
		new_dir = _turn_toward(new_dir, dir, overspeed_steer * delta)
		_set_horizontal(new_dir * move_toward(speed, cap, overspeed_decay * delta))
		return

	if dir.length() > 0.05:
		h = h.move_toward(dir * cap, accel * delta)
	else:
		h = h.move_toward(Vector3.ZERO, friction * delta)
	_set_horizontal(h)


func _air_steer(delta: float, input_dir: Vector3, cap: float) -> void:
	if input_dir.length() < 0.05:
		return
	var h := _horizontal()
	var target := input_dir.normalized() * maxf(cap, h.length())
	_set_horizontal(h.move_toward(target, air_accel * delta))
	facing = _turn_toward(facing, input_dir, hop_turn_speed * delta)


func _input_direction() -> Vector3:
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if raw.length_squared() < 0.0025:
		return Vector3.ZERO
	var dir := Vector3(raw.x, 0.0, raw.y).rotated(Vector3.UP, cam_pivot.rotation.y)
	return dir.limit_length(1.0)


func _launch_speed_for(height: float) -> float:
	return sqrt(2.0 * gravity * maxf(height, 0.0))


func _horizontal() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)


func _set_horizontal(v: Vector3) -> void:
	velocity.x = v.x
	velocity.z = v.z


static func _turn_toward(from: Vector3, to: Vector3, max_radians: float) -> Vector3:
	var a := from.normalized()
	var b := to.normalized()
	if a.is_zero_approx():
		return b
	if b.is_zero_approx():
		return a
	var angle := clampf(a.signed_angle_to(b, Vector3.UP), -max_radians, max_radians)
	return a.rotated(Vector3.UP, angle)


func _consume_leap() -> bool:
	if _buffered_leap <= 0.0:
		return false
	_buffered_leap = 0.0
	return true


func _tick_timers(delta: float) -> void:
	_buffered_leap = maxf(0.0, _buffered_leap - delta)
	_spit_timer = maxf(0.0, _spit_timer - delta)
	_spit_kick = maxf(0.0, _spit_kick - delta * 7.0)
	if momentum_timer > 0.0:
		momentum_timer = maxf(0.0, momentum_timer - delta)
		if is_zero_approx(momentum_timer):
			momentum_speed = 0.0
			momentum_charge = 0.0


## Transitions worth hearing are voiced here rather than in the handlers, because several
## handlers can reach the same state and each one would have to remember to make the noise.
func _set_state(new_state: int) -> void:
	var was := state
	state = new_state
	if was == new_state:
		return

	var fell_from := was in [State.SCURRY_AIR, State.HOP_AIR, State.HOP_PARASAIL]
	var arrived := new_state in [State.SCURRY_GROUND, State.HOP_GROUND]
	# A drum landing is deliberately silent here: its own boom is the landing.
	if fell_from and arrived:
		var force := clampf(_air_fall / 22.0, 0.0, 1.0)
		Sfx.play("land", lerpf(-19.0, -5.0, force), lerpf(1.18, 0.84, force))


## Dropping out of the level scatters part of the load. The manual respawn key stays a
## clean debug reset, or it would just be a free way to dodge the penalty.
func _fall_out() -> void:
	GameState.spill_pouch(pouch_loss_on_fall)
	_respawn()


func _respawn() -> void:
	velocity = Vector3.ZERO
	global_transform = _spawn_transform
	momentum_speed = 0.0
	momentum_timer = 0.0
	momentum_charge = 0.0
	charge = 0.0
	_apply_stance(Stance.HOP)
	_set_state(State.HOP_GROUND)


# --- presentation ------------------------------------------------------------


func _update_pose(delta: float) -> void:
	var weight := 1.0 - exp(-pose_speed * delta)

	var pose: Dictionary = POSE_SCURRY if stance == Stance.SCURRY else POSE_HOP
	for part in pose:
		var node: Node3D = body.get_node(part)
		var target: Dictionary = pose[part]
		var rot: Vector3 = target["rot"]
		# Fold the spit recoil into the head's target rather than adding it afterwards, so
		# it settles back on its own instead of fighting the pose lerp.
		if part == "Head":
			rot += Vector3(-spit_kick_deg * _spit_kick, 0.0, 0.0)
		node.position = node.position.lerp(target["pos"], weight)
		node.rotation_degrees = node.rotation_degrees.lerp(rot, weight)
		node.scale = node.scale.lerp(target["scale"], weight)

	# Compressing for a leap dips the whole body so charge level is readable at a glance.
	var dip := 0.0
	if state == State.HOP_CROUCH:
		dip = -crouch_dip * charge_ratio()
	body.position.y = lerpf(body.position.y, dip, weight)

	var target_yaw := atan2(-facing.x, -facing.z)
	body.rotation.y = lerp_angle(body.rotation.y, target_yaw, 1.0 - exp(-facing_speed * delta))

	var ears := EAR_HOP
	if state == State.HOP_PARASAIL:
		ears = EAR_PARASAIL
	elif stance == Stance.SCURRY:
		ears = EAR_SCURRY
	ear_l.rotation_degrees = ear_l.rotation_degrees.lerp(ears, weight)
	ear_r.rotation_degrees = ear_r.rotation_degrees.lerp(
		Vector3(ears.x, ears.y, -ears.z), weight
	)

	var cheek := Vector3.ONE * _cheek_scale
	cheek_l.scale = cheek_l.scale.lerp(cheek, weight)
	cheek_r.scale = cheek_r.scale.lerp(cheek, weight)


## Cheeks track what is actually being carried, so they swell on the way out and deflate at
## the burrow. Reading the pouch off the character is the point of having pouches.
func _on_pouch_changed(_pouch: int, _capacity: int) -> void:
	_cheek_scale = lerpf(1.0, cheek_max_scale, GameState.pouch_ratio())


# --- level hooks -------------------------------------------------------------


func set_on_trail(value: bool) -> void:
	on_trail = value


func is_scurrying() -> bool:
	return stance == Stance.SCURRY


func horizontal_speed() -> float:
	return _horizontal().length()


func charge_ratio() -> float:
	if state != State.HOP_CROUCH:
		return momentum_charge
	return maxf(charge / maxf(charge_time, 0.001), momentum_charge)


func momentum_ratio() -> float:
	if momentum_window <= 0.0:
		return 0.0
	return momentum_timer / momentum_window


func state_label() -> String:
	match state:
		State.SCURRY_GROUND:
			return "Scurry"
		State.SCURRY_AIR:
			return "Scurry (air)"
		State.HOP_GROUND:
			return "Stand"
		State.HOP_CROUCH:
			return "Crouch"
		State.HOP_AIR:
			return "Airborne"
		State.HOP_PARASAIL:
			return "Parasail"
		State.HOP_DRUM:
			return "Drum"
	return "?"
