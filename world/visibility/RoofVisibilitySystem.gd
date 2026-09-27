## System that manages roof transparency based on camera distance
extends Node
class_name RoofVisibilitySystem

const ProceduralStructure = preload("res://world/objects/ProceduralStructure.gd")

@export var camera_path: NodePath  # Path to Camera3D node
@export var update_radius: float = 30.0  # Only update structures within this radius
@export var fade_start_distance: float = 8.0  # Distance where roof starts fading
@export var fade_end_distance: float = 3.0  # Distance where roof is fully transparent
@export var update_interval: float = 0.1  # Update every N seconds (optimization)

var camera: Camera3D = null
var structures: Array[ProceduralStructure] = []
var time_since_update: float = 0.0

func _ready():
	# Find camera
	if camera_path:
		camera = get_node_or_null(camera_path)

	if not camera:
		# Try to find camera in scene
		camera = _find_camera_in_tree()

	# Find all structures
	_refresh_structures()

func _process(delta):
	time_since_update += delta

	# Update on interval for performance
	if time_since_update < update_interval:
		return

	time_since_update = 0.0

	if not camera or not is_instance_valid(camera):
		camera = _find_camera_in_tree()
		return

	_update_roof_visibility()

## Update roof visibility for all nearby structures
func _update_roof_visibility():
	var camera_pos = camera.global_position

	for structure in structures:
		if not is_instance_valid(structure):
			continue

		var distance = camera_pos.distance_to(structure.global_position)

		# Skip structures far from camera (optimization)
		if distance > update_radius:
			# Reset to full opacity if it was previously transparent
			if distance < update_radius * 1.5:  # Hysteresis zone
				structure.reset_roof_visibility()
			continue

		# Update roof transparency based on distance
		structure.update_roof_visibility(distance, fade_start_distance, fade_end_distance)

## Refresh list of structures in the scene
func _refresh_structures():
	structures.clear()

	# Find all ProceduralStructure nodes in tree
	_find_structures_recursive(get_tree().root)

	print("[RoofVisibilitySystem] Found %d structures with roofs" % structures.size())

## Recursively find all ProceduralStructure nodes
func _find_structures_recursive(node: Node):
	if node is ProceduralStructure:
		var structure = node as ProceduralStructure
		# Only track structures that have roofs
		if not structure.roof_parts.is_empty():
			structures.append(structure)

	for child in node.get_children():
		_find_structures_recursive(child)

## Find camera in scene tree
func _find_camera_in_tree() -> Camera3D:
	return _find_camera_recursive(get_tree().root)

func _find_camera_recursive(node: Node) -> Camera3D:
	if node is Camera3D and (node as Camera3D).current:
		return node as Camera3D

	for child in node.get_children():
		var result = _find_camera_recursive(child)
		if result:
			return result

	return null

## Call this when new structures are added to the scene
func add_structure(structure: ProceduralStructure):
	if not structures.has(structure) and not structure.roof_parts.is_empty():
		structures.append(structure)

## Call this when map is regenerated
func clear_structures():
	structures.clear()
