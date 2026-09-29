## Peel Trap (Banana): tosses a banana peel where you aim. The first enemy who steps on it slips:
## slides on helplessly (stunned) and takes a knock. A banana keeps MAX_PEELS peels out at a time;
## they rot after BananaPeel.LIFETIME. Only the server's peel catches people (BananaPeel.authority).
extends ActiveAbility
class_name PeelTrap

const MAX_PEELS: int = 2
const FLIGHT_TIME: float = 0.3

func aim_preview() -> Dictionary:
	return {"shape": "circle", "range": max_range, "radius": 0.8}

func _init():
	ability_name = "Peel Trap"
	cooldown = 8.0
	duration = 0.3
	max_range = 6.0

func _on_activate(entity, target_position: Vector3) -> bool:
	var parent = AbilityFX._parent(entity)
	if not parent:
		return false
	var spot = AbilityFX._ground(entity, target_position)
	AbilityFX.throw_blob(entity, entity.global_position + Vector3(0, 1.0, 0), spot, Color(1.0, 0.88, 0.3), FLIGHT_TIME)
	if entity.is_inside_tree():
		await entity.get_tree().create_timer(FLIGHT_TIME).timeout
	if not is_instance_valid(entity) or not entity.is_inside_tree() or not is_instance_valid(parent):
		return true
	# The oldest of this banana's peels goes if there are too many
	var mine: Array = []
	for peel in entity.get_tree().get_nodes_in_group("banana_peels"):
		if peel.owner_entity == entity and not peel.is_queued_for_deletion():
			mine.append(peel)
	while mine.size() >= MAX_PEELS:
		mine.pop_front().rot()
	var peel = BananaPeel.new()
	peel.owner_entity = entity
	var mp = entity.get_tree().get_multiplayer()
	peel.authority = not replay and (not mp.has_multiplayer_peer() or mp.is_server())
	parent.add_child(peel)
	peel.global_position = spot
	return true
