class_name Ballistics
extends RefCounted

## Shared arc maths for the spit.
##
## The reticle, the lock-on and the projectile itself all have to agree about where a seed
## will land. When they disagreed the reticle marked a point the seed never passed through,
## which is unlearnable by definition, so the arc lives in exactly one place now.

## Layer 1 is the world, layer 2 is spit targets.
const SPIT_MASK := 1 | 2


## Where a shot fired from `from` along `dir` ends up.
##
## Steps the arc in slices and sweeps each slice with a ray, which is how the projectile
## moves as well, so prediction and reality are the same computation at different
## resolutions.
static func trace(
	world: World3D,
	from: Vector3,
	dir: Vector3,
	speed: float,
	gravity: float,
	exclude: Array[RID] = [],
	max_time := 1.6,
	## Matches the physics tick the projectile itself integrates on. A coarser step would be
	## cheaper, but then the marker and the seed would accumulate different drop and the
	## reticle would drift back into lying at long range.
	step := 1.0 / 60.0
) -> Dictionary:
	var pos := from
	var vel := dir.normalized() * speed
	var space := world.direct_space_state
	var elapsed := 0.0

	while elapsed < max_time:
		elapsed += step
		vel.y -= gravity * step
		var next := pos + vel * step
		var query := PhysicsRayQueryParameters3D.create(pos, next)
		query.collision_mask = SPIT_MASK
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return {"position": hit["position"], "collider": hit["collider"], "hit": true}
		pos = next

	return {"position": pos, "collider": null, "hit": false}


## Launch elevation that puts a shot through a point `d` away horizontally and `h` above the
## muzzle, taking the flat arc of the two solutions. Returns NAN when it is out of reach.
static func elevation_to(d: float, h: float, speed: float, gravity: float) -> float:
	if d < 0.01:
		return PI * 0.5 if h >= 0.0 else -PI * 0.5
	var v2 := speed * speed
	var disc := v2 * v2 - gravity * (gravity * d * d + 2.0 * h * v2)
	if disc < 0.0:
		return NAN
	return atan2(v2 - sqrt(disc), gravity * d)


## Direction to fire in so the shot lands on `target`. Falls back to pointing straight at it
## when the target is beyond the range the arc can reach.
static func direction_to(
	muzzle: Vector3, target: Vector3, speed: float, gravity: float
) -> Vector3:
	var delta := target - muzzle
	var flat := Vector3(delta.x, 0.0, delta.z)
	var d := flat.length()
	if d < 0.01:
		return Vector3.UP if delta.y >= 0.0 else Vector3.DOWN

	var pitch := elevation_to(d, delta.y, speed, gravity)
	if is_nan(pitch):
		return delta.normalized()
	return (flat / d * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
