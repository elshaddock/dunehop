extends CanvasLayer

## Prototype readout.
##
## The banked-momentum meter is still the important one, since the conversion window is
## invisible otherwise and you cannot learn to time something you cannot see. The pouch row
## is second: it is simultaneously your score, your ammunition and the thing that gets
## heavier as you fill it, so it has to be legible at a glance.

const POUCH_NORMAL := Color(1, 0.855, 0.6)
const POUCH_FULL := Color(1, 0.494, 0.372)

const RETICLE_IDLE := Color(1, 1, 1, 0.34)
const RETICLE_AIMING := Color(1, 1, 1, 0.92)
## Cyan rather than green: the pods are green and the sand is amber, so both of the obvious
## choices would camouflage the reticle against the things it has to be read against.
const RETICLE_LOCKED := Color(0.35, 0.95, 1, 0.97)
const RETICLE_EMPTY := Color(1, 0.45, 0.38, 0.5)

@onready var stored_label: Label = %Stored
@onready var pouch_label: Label = %Pouch
@onready var stance_label: Label = %Stance
@onready var speed_label: Label = %Speed
@onready var charge_bar: ProgressBar = %ChargeBar
@onready var momentum_bar: ProgressBar = %MomentumBar
@onready var reticle: Label = %Reticle
@onready var sunseed_label: Label = %Sunseeds
@onready var toll_panel: PanelContainer = %TollPanel
@onready var toll_label: Label = %TollLabel
@onready var toll_bar: ProgressBar = %TollBar
@onready var banner: Label = %Banner

var _player: Node = null


func _ready() -> void:
	GameState.pouch_changed.connect(_on_pouch_changed)
	GameState.stored_changed.connect(_on_stored_changed)
	GameState.sunseeds_changed.connect(_on_sunseeds_changed)
	GameState.all_sunseeds_found.connect(_on_all_found)
	_on_pouch_changed(GameState.pouch, GameState.pouch_capacity)
	_on_stored_changed(GameState.seeds_stored)
	_on_sunseeds_changed(GameState.sunseeds_found, GameState.sunseeds_total)
	toll_panel.visible = false
	banner.visible = false


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return

	var stance_name := "SCURRY" if _player.is_scurrying() else "HOP"
	stance_label.text = "%s  -  %s" % [stance_name, _player.state_label()]
	speed_label.text = "Speed   %.1f" % _player.horizontal_speed()
	charge_bar.value = _player.charge_ratio()
	momentum_bar.value = _player.momentum_ratio()
	_update_reticle()
	_update_toll()


## Paying a toll is silent otherwise: the barrier sinking is easy to miss while you are
## looking at your own feet, and "why is my seed count dropping" is a bad first thought.
func _update_toll() -> void:
	var gate: Node = null
	for node in get_tree().get_nodes_in_group("seed_gate"):
		if not node.is_open() and node.player_present():
			gate = node
			break

	if gate == null:
		toll_panel.visible = false
		return

	toll_panel.visible = true
	toll_bar.value = float(gate.paid()) / float(maxi(1, gate.cost))
	if GameState.seeds_stored > 0:
		toll_label.text = "%s   %d / %d" % [gate.label, gate.paid(), gate.cost]
		toll_label.add_theme_color_override("font_color", POUCH_NORMAL)
	else:
		# The gate is not broken, you are just carrying nothing it wants.
		toll_label.text = "%s   %d / %d   -  bank seeds at a burrow" % [
			gate.label, gate.paid(), gate.cost
		]
		toll_label.add_theme_color_override("font_color", POUCH_FULL)


## Draw the marker where the seed will actually come down, not at the centre of the screen.
## The camera is tilted for framing and sits behind the player, so screen centre is nowhere
## near the line of fire and a fixed crosshair is simply wrong.
func _update_reticle() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		reticle.visible = false
		return

	var impact: Dictionary = _player.predicted_impact()
	var point: Vector3 = impact["position"]
	if camera.is_position_behind(point):
		reticle.visible = false
		return

	reticle.visible = true
	reticle.position = camera.unproject_position(point) - reticle.size * 0.5

	var locked: Node3D = _player.locked_target()
	if GameState.pouch <= 0:
		reticle.text = "+"
		reticle.add_theme_color_override("font_color", RETICLE_EMPTY)
	elif locked != null:
		reticle.text = "[ ]"
		reticle.add_theme_color_override("font_color", RETICLE_LOCKED)
	else:
		reticle.text = "+"
		reticle.add_theme_color_override(
			"font_color", RETICLE_AIMING if _player.is_aiming() else RETICLE_IDLE
		)


func _on_pouch_changed(pouch: int, capacity: int) -> void:
	var full := pouch >= capacity
	pouch_label.text = "Pouch   %d / %d%s" % [pouch, capacity, "   FULL" if full else ""]
	pouch_label.add_theme_color_override(
		"font_color", POUCH_FULL if full else POUCH_NORMAL
	)


func _on_stored_changed(stored: int) -> void:
	stored_label.text = "Stored   %d" % stored


func _on_sunseeds_changed(found: int, total: int) -> void:
	sunseed_label.text = "Sunseeds   %d / %d" % [found, total]


func _on_all_found() -> void:
	Sfx.play("fanfare", -4.0)
	banner.visible = true
	var tween := create_tween()
	tween.tween_property(banner, "modulate:a", 1.0, 0.4).from(0.0)
