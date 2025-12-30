## Loot chest that players can open
extends Node3D
class_name Chest

signal chest_opened(player: Player)
signal loot_dropped(items: Array)

var is_opened: bool = false
var loot_table: LootTable = null
var loot_items: Array[ItemData] = []

func _ready():
	add_to_group("chests")
	
	# Create visual representation
	_create_visual()

func _create_visual():
	# Create simple box mesh for chest
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1.0, 1.0, 1.0)
	mesh_instance.mesh = box_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.4, 0.2)  # Brown
	mesh_instance.set_surface_override_material(0, material)
	
	add_child(mesh_instance)

func open(player: Player) -> Array[ItemData]:
	if is_opened:
		return []
	
	is_opened = true
	chest_opened.emit(player)
	
	# Generate loot
	if loot_table:
		loot_items = loot_table.generate_loot()
	else:
		# Default loot
		loot_items = _generate_default_loot()
	
	loot_dropped.emit(loot_items)
	
	# Visual feedback
	_animate_open()
	
	return loot_items

func _generate_default_loot() -> Array[ItemData]:
	var items: Array[ItemData] = []
	
	# Random chance for different items
	if randf() < 0.5:
		var health_pack = HealthPack.new()
		items.append(health_pack)
	
	return items

func _animate_open():
	# Animate chest opening
	var tween = create_tween()
	tween.tween_property(self, "rotation_degrees", Vector3(0, 0, -45), 0.3)

func can_be_opened_by(player: Player) -> bool:
	return not is_opened and global_position.distance_to(player.global_position) < 2.0

