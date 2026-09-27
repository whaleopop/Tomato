## Base entity class that holds components
## Uses component-based architecture
## Extends CharacterBody3D for physics support (gravity, collisions)
extends CharacterBody3D
class_name Entity

signal component_added(component)  # component: Component
signal component_removed(component)  # component: Component

var components: Dictionary = {}
var entity_id: int = -1
var is_server_authoritative: bool = false

func _ready():
	# Set collision layer for player detection (layer 2)
	# Layer 1 = environment, Layer 2 = players, Layer 3 = items
	collision_layer = 2
	collision_mask = 1 | 4  # Collide with environment (1) and items (4)

	# Setup collision shape if not present
	if not has_node("CollisionShape3D"):
		_create_default_collision()

func _physics_process(delta: float):
	# Process components
	for component in components.values():
		if component.enabled:
			component.update(delta)

func _create_default_collision():
	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.2
	collision.shape = capsule
	collision.position = Vector3(0, 0.6, 0)  # Center at player height
	add_child(collision)

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

