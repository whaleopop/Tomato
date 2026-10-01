## Server-side fog of war (anti-wallhack): who may know where somebody else is.
## The world state for each client only carries the positions of players it can see
## (TickSystem); everyone else arrives as {"hidden": true} with just their health.
## Same rules as the client's VisibilitySystem - weapon sight radius in hexes, cover walls cut
## the line, a bush hides you unless the viewer is right next to you - plus a margin so players
## are already known a moment before the client's fog would reveal them.
extends RefCounted
class_name ServerVisibility

const MARGIN: float = 2.6  # world units beyond the sight radius
const REVEAL_TIME: float = 0.8  # seconds after shooting / casting you can't hide in a bush
const HEAR_DISTANCE: float = 26.0  # shots and casts reach clients this close (world units)

static func can_see(viewer: Node3D, target: Node3D, grid: HexGrid) -> bool:
	if not is_instance_valid(viewer) or not is_instance_valid(target) or not viewer.is_inside_tree() or not target.is_inside_tree():
		return false
	if viewer == target:
		return true
	# The eliminated spectate the whole map; the fallen are no secret (and invisible anyway)
	if _is_dead(viewer) or _is_dead(target):
		return true
	# Team modes: your team is always in sight; a flag carrier is seen by everyone
	if viewer.has_meta("team") and target.has_meta("team") and int(viewer.get_meta("team")) == int(target.get_meta("team")):
		return true
	if target.has_meta("flag_carrier"):
		return true

	var radius = VisibilitySystem.BASE_VISIBILITY_RANGE
	var combat = viewer.get_component("CombatComponent")
	if combat and combat.equipped_ranged_weapon:
		radius = combat.equipped_ranged_weapon.visibility_range
	# Night / fog (MapEvents) and blindness: the same shorter sight as the client's fog
	var viewer_status = viewer.get_component("StatusComponent")
	radius *= MapEvents.sight_factor * (viewer_status.sight_factor() if viewer_status else 1.0)
	radius *= VisibilitySystem.high_ground_factor(viewer.global_position.y) * BiomeRules.sight_factor(grid, viewer.global_position)
	radius = max(radius, VisibilitySystem.ALWAYS_SEEN + VisibilitySystem.FOG_FADE_DISTANCE * 0.5)
	# Small Target passive: spotted only from part of the usual distance
	if target.has_meta("small_target"):
		radius *= float(target.get_meta("small_target"))
	# Stealth (Grape Decoy): only right next to them
	var target_status = target.get_component("StatusComponent")
	if target_status and target_status.is_stealthed() and viewer.global_position.distance_to(target.global_position) > StatusComponent.STEALTH_REVEAL:
		return false

	var d = _hex_distance(grid, viewer.global_position, target.global_position)
	if d > VisibilitySystem.to_hexes(radius + MARGIN):
		return false
	if d <= VisibilitySystem.to_hexes(VisibilitySystem.ALWAYS_SEEN):
		return true

	var eye = Vector3(0, VisibilitySystem.EYE_HEIGHT, 0)
	if CoverSpawner.line_blocked(viewer.get_world_3d(), viewer.global_position + eye, target.global_position + eye):
		return false

	# At night bushes hide better: you must come closer, a shot gives you away for a shorter time
	var revealed = Time.get_ticks_msec() / 1000.0 - float(target.get_meta("last_reveal_time", -100.0)) < REVEAL_TIME * MapEvents.bush_factor
	if not revealed and (Bush.any_contains(viewer.get_tree(), target.global_position) or BiomeRules.hides(grid, target.global_position)) \
			and viewer.global_position.distance_to(target.global_position) >= VisibilitySystem.BUSH_REVEAL_DISTANCE * MapEvents.bush_factor:
		return false
	return true

## Does this client get to hear about an event at `pos` (tracer, ability effect)?
static func can_hear(viewer: Node3D, pos: Vector3) -> bool:
	if not is_instance_valid(viewer) or not viewer.is_inside_tree():
		return false
	if _is_dead(viewer):
		return true
	return viewer.global_position.distance_to(pos) <= HEAR_DISTANCE

static func _is_dead(node: Node3D) -> bool:
	var health = node.get_component("HealthComponent") if node.has_method("get_component") else null
	return health != null and health.is_dead

static func _hex_distance(grid: HexGrid, a: Vector3, b: Vector3) -> float:
	if not grid:
		return VisibilitySystem.to_hexes(a.distance_to(b))
	var ha = grid.world_to_hex(a)
	var hb = grid.world_to_hex(b)
	var dq = ha.x - hb.x
	var dr = ha.y - hb.y
	return float(max(abs(dq), abs(dr), abs(dq + dr)))
