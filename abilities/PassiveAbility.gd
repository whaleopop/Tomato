## Base class for passive abilities
extends Ability
class_name PassiveAbility

signal ability_applied
signal ability_removed

var is_applied: bool = false

func apply(entity):  # entity: Entity
	if not enabled or is_applied:
		return
	
	is_applied = true
	_on_apply(entity)
	ability_applied.emit()

func remove(entity):  # entity: Entity
	if not is_applied:
		return
	
	is_applied = false
	_on_remove(entity)
	ability_removed.emit()

func _on_apply(entity):  # entity: Entity
	pass

func _on_remove(entity):  # entity: Entity
	pass

