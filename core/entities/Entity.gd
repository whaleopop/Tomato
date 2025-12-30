## Base entity class that holds components
## Uses component-based architecture
extends Node3D
class_name Entity

signal component_added(component)  # component: Component
signal component_removed(component)  # component: Component

var components: Dictionary = {}
var entity_id: int = -1
var is_server_authoritative: bool = false

func _ready():
	pass

func _process(delta: float):
	for component in components.values():
		if component.enabled:
			component.update(delta)

## Add a component to this entity
func add_component(component) -> bool:  # component: Component
	if component == null:
		return false
	
	var component_name = component.get_script().get_path().get_file().get_basename()
	
	if components.has(component_name):
		push_warning("Component %s already exists on entity %s" % [component_name, name])
		return false
	
	component.set_entity(self)
	components[component_name] = component
	component.enable()  # Enable component and emit its signal
	component_added.emit(component)
	return true

## Remove a component from this entity
func remove_component(component_name: String) -> bool:
	if not components.has(component_name):
		return false
	
	var component = components[component_name]
	component.disable()
	components.erase(component_name)
	component_removed.emit(component)
	return true

## Get a component by name
func get_component(component_name: String):  # -> Component
	return components.get(component_name, null)

## Check if entity has a component
func has_component(component_name: String) -> bool:
	return components.has(component_name)

