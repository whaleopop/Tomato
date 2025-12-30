## Base component class for entity-component system
## All components inherit from this class
extends RefCounted
class_name Component

signal component_enabled
signal component_disabled

var entity = null  # Entity
var enabled: bool = true

func _init(p_entity = null):  # Entity
	entity = p_entity

func enable():
	if not enabled:
		enabled = true
		component_enabled.emit()

func disable():
	if enabled:
		enabled = false
		component_disabled.emit()

func update(delta: float):
	pass

func get_entity():
	return entity

func set_entity(p_entity):
	entity = p_entity
