## Base class for active abilities
extends Ability
class_name ActiveAbility

signal ability_activated
signal ability_finished

var duration: float = 0.0
var is_active: bool = false
var max_range: float = 0.0  # > 0: targets further away are pulled in to this distance

func activate(entity, target_position: Vector3 = Vector3.ZERO) -> bool:  # entity: Entity
	if not enabled or is_active:
		return false

	# No casting at the far end of the map (or through the whole screen)
	if max_range > 0.0 and entity and is_instance_valid(entity) and target_position != Vector3.ZERO:
		var offset = target_position - entity.global_position
		offset.y = 0.0
		if offset.length() > max_range:
			target_position = entity.global_position + offset.normalized() * max_range

	is_active = true
	ability_activated.emit()

	# _on_activate may wait (Turnip Toss): without await its result was a function state object
	var success = await _on_activate(entity, target_position)
	if success != true:
		is_active = false
		return false

	if duration > 0.0:
		if entity and is_instance_valid(entity) and entity is Node:
			var tree = entity.get_tree()
			if tree:
				await tree.create_timer(duration).timeout
		else:
			# Fallback: use SceneTree if available
			var scene_tree = Engine.get_main_loop()
			if scene_tree is SceneTree:
				await scene_tree.create_timer(duration).timeout
		deactivate(entity)
	else:
		deactivate(entity)  # instant abilities end right away (is_active used to stick)

	return true

func deactivate(entity):  # entity: Entity
	if not is_active:
		return
	
	is_active = false
	_on_deactivate(entity)
	ability_finished.emit()

func _on_activate(entity, target_position: Vector3) -> bool:  # entity: Entity
	return true

func _on_deactivate(entity):  # entity: Entity
	pass
