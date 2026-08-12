extends Node3D

## Stance-aware follow camera. Sits directly under the player so it tracks position
## without inheriting the body's facing rotation (the player node itself never turns,
## only its Body child does).
##
## Scurry gets a low, close framing that sells speed. Hop pulls back and lifts so the
## vertical space you are about to launch into is actually on screen. The two framings
## blend rather than cutting.

@export_group("Scurry framing")
@export var scurry_distance := 4.6
@export var scurry_height := 0.85
@export var scurry_pitch_deg := -6.0

@export_group("Hop framing")
@export var hop_distance := 6.6
@export var hop_height := 1.55
@export var hop_pitch_deg := -13.0

@export_group("Look")
@export var mouse_sensitivity := 0.0022
@export var stick_speed := 2.6
@export var min_pitch_deg := -68.0
## Generous upward range because this doubles as the spit's elevation: pods are hung out
## of reach, and a 30-degree ceiling would put half of them behind an invisible wall.
@export var max_pitch_deg := 50.0
@export var frame_blend := 5.0

@export_group("Aim")
@export var aim_distance := 2.8
@export var aim_height := 1.42
## Slide off-centre so the creature is not standing in front of what you are shooting at.
@export var aim_shoulder := 0.8
## Zero on purpose. Outside aim mode the framing tilts down to compose the shot, but while
## aiming that tilt would separate the view from the line of fire again.
@export var aim_pitch_deg := 0.0
@export var aim_sensitivity_scale := 0.45
@export var aim_blend := 14.0

@export_group("Recoil")
@export var kick_per_shot := 0.035
@export var kick_max := 0.09
@export var kick_recover := 7.0

@export_group("Auto align")
## Swinging the camera behind a fast scurry is the main thing separating a platformer
## camera from a debug view, but it must never fight a player who is actively looking.
@export var align_speed := 2.4
@export var align_min_speed := 6.0
@export var align_idle_delay := 0.7

var aiming := false

var _yaw := 0.0
var _pitch := 0.0
var _pitch_bias := 0.0
var _look_idle := 999.0
var _kick := 0.0

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var arm: SpringArm3D = $SpringArm3D


func _ready() -> void:
	_yaw = rotation.y
	_pitch_bias = deg_to_rad(hop_pitch_deg)
	arm.add_excluded_object(player.get_rid())
	arm.spring_length = hop_distance
	position.y = hop_height
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := mouse_sensitivity * (aim_sensitivity_scale if aiming else 1.0)
		_yaw -= event.relative.x * sensitivity
		_pitch -= event.relative.y * sensitivity
		_look_idle = 0.0


func _process(delta: float) -> void:
	aiming = Input.is_action_pressed("aim")
	_kick = move_toward(_kick, 0.0, kick_recover * delta)
	_read_stick(delta)
	_auto_align(delta)
	_apply_framing(delta)


func _read_stick(delta: float) -> void:
	var stick := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if stick.length() > 0.15:
		_yaw -= stick.x * stick_speed * delta
		_pitch -= stick.y * stick_speed * delta
		_look_idle = 0.0
	else:
		_look_idle += delta


func _auto_align(delta: float) -> void:
	# Swinging the camera on its own while the player is lining up a shot is intolerable.
	if aiming:
		return
	if player == null or _look_idle < align_idle_delay:
		return
	if not player.is_scurrying() or player.horizontal_speed() < align_min_speed:
		return
	var heading := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if heading.length() < 0.1:
		return
	heading = heading.normalized()
	var target_yaw := atan2(-heading.x, -heading.z)
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-align_speed * delta))


func _apply_framing(delta: float) -> void:
	var scurrying: bool = player != null and player.is_scurrying()
	var target_distance := scurry_distance if scurrying else hop_distance
	var target_height := scurry_height if scurrying else hop_height
	var target_bias := deg_to_rad(scurry_pitch_deg if scurrying else hop_pitch_deg)
	var target_shoulder := 0.0
	var blend := frame_blend

	if aiming:
		target_distance = aim_distance
		target_height = aim_height
		target_bias = deg_to_rad(aim_pitch_deg)
		target_shoulder = aim_shoulder
		blend = aim_blend

	var weight := 1.0 - exp(-blend * delta)
	arm.spring_length = lerpf(arm.spring_length, target_distance, weight)
	arm.position.x = lerpf(arm.position.x, target_shoulder, weight)
	position.y = lerpf(position.y, target_height, weight)
	_pitch_bias = lerpf(_pitch_bias, target_bias, weight)

	var lo := deg_to_rad(min_pitch_deg)
	var hi := deg_to_rad(max_pitch_deg)
	_pitch = clampf(_pitch, lo, hi)

	rotation.y = _yaw
	# The kick is deliberately kept out of aim_direction below: recoil should shake the view
	# without walking your aim off the target between shots.
	rotation.x = clampf(_pitch + _pitch_bias + _kick, lo, hi)


func kick() -> void:
	_kick = minf(_kick + kick_per_shot, kick_max)


## Where the player is deliberately looking, for the spit to travel along.
##
## This excludes the stance framing tilt on purpose. That tilt exists to compose the shot,
## not to express intent, and folding it in would make a neutral look spit at the dirt a
## few metres ahead.
func aim_direction() -> Vector3:
	return Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Vector3.FORWARD
