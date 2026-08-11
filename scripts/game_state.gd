extends Node

## Autoloaded run state. Seeds register themselves on spawn so the HUD can show a
## denominator without the level having to hand-maintain a count.

signal seeds_changed(collected: int, total: int)

var seeds_collected: int = 0
var seeds_total: int = 0


func register_seed() -> void:
	seeds_total += 1
	seeds_changed.emit(seeds_collected, seeds_total)


func collect_seed() -> void:
	seeds_collected += 1
	seeds_changed.emit(seeds_collected, seeds_total)


func reset_counts() -> void:
	seeds_collected = 0
	seeds_total = 0
	seeds_changed.emit(seeds_collected, seeds_total)
