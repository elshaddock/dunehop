extends Node

## Autoloaded run state and the seed economy.
##
## Seeds live in two pools and the whole loop comes from the gap between them. The pouch is
## what is physically in your cheeks: it is capped, it is what the spit spends, and part of
## it scatters if you fall. Stored seeds are what you have carried home to a burrow, and
## those can never be lost.
##
## There is deliberately no fixed "collect them all" denominator. Spit turns seeds into
## ammunition and pods turn ammunition back into seeds, so the number in the world is not a
## constant and pretending otherwise would just produce a counter that lies.

signal pouch_changed(pouch: int, capacity: int)
signal stored_changed(stored: int)
signal pickup_refused()
signal seeds_deposited(count: int)

## Seeds placed in the level at load. Kept for reference, not shown as a denominator.
var seeds_total: int = 0
var seeds_stored: int = 0
var pouch: int = 0
var pouch_capacity: int = 8


func register_seed() -> void:
	seeds_total += 1


func pouch_space() -> int:
	return maxi(0, pouch_capacity - pouch)


func is_pouch_full() -> bool:
	return pouch_space() <= 0


## Returns false when the cheeks are already full. Callers are expected to leave the seed
## in the world rather than quietly destroying it, so a full pouch reads as "come back for
## this" instead of as a broken pickup.
func pocket_seed() -> bool:
	if is_pouch_full():
		pickup_refused.emit()
		return false
	pouch += 1
	pouch_changed.emit(pouch, pouch_capacity)
	return true


## Bulk intake for a burst pod. Returns how many actually fit.
func pocket_seeds(count: int) -> int:
	var taken := mini(count, pouch_space())
	if taken <= 0:
		pickup_refused.emit()
		return 0
	pouch += taken
	pouch_changed.emit(pouch, pouch_capacity)
	return taken


func spend_seed() -> bool:
	if pouch <= 0:
		return false
	pouch -= 1
	pouch_changed.emit(pouch, pouch_capacity)
	return true


func deposit_pouch() -> int:
	if pouch <= 0:
		return 0
	var moved := pouch
	pouch = 0
	seeds_stored += moved
	pouch_changed.emit(pouch, pouch_capacity)
	stored_changed.emit(seeds_stored)
	seeds_deposited.emit(moved)
	return moved


## Falling scatters part of the load. Without a cost for going down, walking home to a
## burrow would be bookkeeping rather than a decision.
func spill_pouch(fraction: float) -> int:
	if pouch <= 0:
		return 0
	var lost := int(floor(float(pouch) * clampf(fraction, 0.0, 1.0)))
	if lost <= 0:
		return 0
	pouch -= lost
	pouch_changed.emit(pouch, pouch_capacity)
	return lost


func clear_pouch() -> void:
	if pouch == 0:
		return
	pouch = 0
	pouch_changed.emit(pouch, pouch_capacity)


func pouch_ratio() -> float:
	if pouch_capacity <= 0:
		return 0.0
	return float(pouch) / float(pouch_capacity)


func reset_counts() -> void:
	seeds_total = 0
	seeds_stored = 0
	pouch = 0
	pouch_changed.emit(pouch, pouch_capacity)
	stored_changed.emit(seeds_stored)
