extends CanvasLayer

## Prototype readout.
##
## The banked-momentum meter is still the important one, since the conversion window is
## invisible otherwise and you cannot learn to time something you cannot see. The pouch row
## is second: it is simultaneously your score, your ammunition and the thing that gets
## heavier as you fill it, so it has to be legible at a glance.

const POUCH_NORMAL := Color(1, 0.855, 0.6)
const POUCH_FULL := Color(1, 0.494, 0.372)

@onready var stored_label: Label = %Stored
@onready var pouch_label: Label = %Pouch
@onready var stance_label: Label = %Stance
@onready var speed_label: Label = %Speed
@onready var charge_bar: ProgressBar = %ChargeBar
@onready var momentum_bar: ProgressBar = %MomentumBar

var _player: Node = null


func _ready() -> void:
	GameState.pouch_changed.connect(_on_pouch_changed)
	GameState.stored_changed.connect(_on_stored_changed)
	_on_pouch_changed(GameState.pouch, GameState.pouch_capacity)
	_on_stored_changed(GameState.seeds_stored)


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


func _on_pouch_changed(pouch: int, capacity: int) -> void:
	var full := pouch >= capacity
	pouch_label.text = "Pouch   %d / %d%s" % [pouch, capacity, "   FULL" if full else ""]
	pouch_label.add_theme_color_override(
		"font_color", POUCH_FULL if full else POUCH_NORMAL
	)


func _on_stored_changed(stored: int) -> void:
	stored_label.text = "Stored   %d" % stored
