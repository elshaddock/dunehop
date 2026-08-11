extends CanvasLayer

## Prototype readout. The banked meter is the important one: the conversion window is
## invisible otherwise, and you cannot learn to time something you cannot see.

@onready var seeds_label: Label = %Seeds
@onready var stance_label: Label = %Stance
@onready var speed_label: Label = %Speed
@onready var charge_bar: ProgressBar = %ChargeBar
@onready var momentum_bar: ProgressBar = %MomentumBar

var _player: Node = null


func _ready() -> void:
	GameState.seeds_changed.connect(_on_seeds_changed)
	_on_seeds_changed(GameState.seeds_collected, GameState.seeds_total)


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


func _on_seeds_changed(collected: int, total: int) -> void:
	seeds_label.text = "Seeds   %d / %d" % [collected, total]
