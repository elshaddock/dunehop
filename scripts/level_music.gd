extends AudioStreamPlayer

## The level's music bed.
##
## Deliberately not Godot's `autoplay`. Headless runs get the Dummy audio driver, which never
## hands its playbacks back at exit, so an autoplaying track turns every clean harness run into
## a leaked-instance warning. Sfx skips its voices in headless for the same reason.
##
## Looping is an import setting on the ogg rather than something set here, so the loop belongs
## to the asset and cannot be silently lost by a node that forgets to ask for it.

## Faded up rather than started at full, since the level fades in from the menu-less black of a
## cold boot and a track snapping to full volume on frame one reads as a glitch.
@export var fade_in := 2.0
@export var level_db := -14.0
## Dropped to this while the completion fanfare plays, so the one moment the game congratulates
## you is not competing with the backing track.
@export var duck_db := -26.0
@export var duck_time := 0.6
## Long enough to cover the fanfare before the bed comes back up under it.
@export var duck_hold := 2.0
@export var recover_time := 2.5

var _tween: Tween = null


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	GameState.all_sunseeds_found.connect(_duck)
	volume_db = -60.0
	play()
	_retune().tween_property(self, "volume_db", level_db, fade_in)


## Stopping alone is not enough: a held playback keeps the stream that fed it alive, so quitting
## mid-track reports resources still in use. Dropping the reference too hands both back.
func _exit_tree() -> void:
	stop()
	stream = null


## Get out of the way of the fanfare, then come back.
##
## Written as one tween rather than a fade, an awaited timer and a second fade: a coroutine
## suspended on a SceneTreeTimer at shutdown is exactly the leak this project already had to
## chase out of the seed pods.
func _duck() -> void:
	var move := _retune()
	move.tween_property(self, "volume_db", duck_db, duck_time)
	move.tween_interval(duck_hold)
	move.tween_property(self, "volume_db", level_db, recover_time)


## One tween at a time, or a duck landing mid-fade leaves two of them fighting over the same
## property and the volume settles wherever the slower one happens to finish.
func _retune() -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	return _tween
