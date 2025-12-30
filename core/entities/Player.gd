## Player entity with all components
extends "res://core/entities/Entity.gd"
class_name Player

signal player_ready
signal player_spawned

var player_name: String = ""
var character_data: CharacterData = null
var is_local_player: bool = false

func _ready():
	super._ready()
	add_to_group("players")
	add_to_group("entities")
	
	# Initialize components
	_initialize_components()
	
	player_ready.emit()

func _initialize_components():
	# Health component
	var health = HealthComponent.new(self, 100.0)
	add_component(health)
	
	# Movement component
	var movement = MovementComponent.new(self)
	add_component(movement)
	
	# Combat component
	var combat = CombatComponent.new(self)
	add_component(combat)
	
	# Ability component
	var ability = AbilityComponent.new(self)
	add_component(ability)
	
	# Inventory component
	var inventory = InventoryComponent.new(self, 10)
	add_component(inventory)
	
	# Networking component
	var networking = NetworkingComponent.new(self)
	add_component(networking)

func setup_character(data: CharacterData):
	character_data = data

	if data == null:
		return

	# Apply character stats
	var health = get_component("HealthComponent")
	if health:
		health.set_max_health(data.base_health, true)

	var movement = get_component("MovementComponent")
	if movement:
		movement.set_speed(data.base_speed)

	# Load character model with normalization
	_load_character_model(data)

	# Setup abilities
	var ability_component = get_component("AbilityComponent")
	if ability_component:
		# Add active ability
		if data.active_ability:
			var active_ability = _create_ability_from_data(data.active_ability)
			if active_ability:
				ability_component.add_active_ability(active_ability)

		# Add passive ability
		if data.passive_ability:
			var passive_ability = _create_ability_from_data(data.passive_ability)
			if passive_ability is PassiveAbility:
				ability_component.add_passive_ability(passive_ability)

func _load_character_model(data: CharacterData):
	if data.model_path == "" or not ResourceLoader.exists(data.model_path):
		print("[Player] No model found at: %s" % data.model_path)
		return

	var model_scene = load(data.model_path)
	if not model_scene:
		print("[Player] Failed to load model: %s" % data.model_path)
		return

	# Create model container for proper positioning
	var model_container = Node3D.new()
	model_container.name = "Model"

	var model_instance = model_scene.instantiate()
	model_instance.name = "ModelMesh"

	# Apply scale normalization (target height ~1.2m)
	var target_height: float = 1.2
	var scale_factor = data.model_scale if data.model_scale > 0 else 1.0

	# Auto-calculate scale if needed based on AABB
	if scale_factor == 1.0:
		# Try to get model bounds after adding to scene
		model_container.add_child(model_instance)
		var aabb = _get_model_aabb(model_instance)
		if aabb.size.y > 0:
			scale_factor = target_height / aabb.size.y
			print("[Player] Auto-calculated scale: %f (model height: %f)" % [scale_factor, aabb.size.y])
	else:
		model_container.add_child(model_instance)

	model_instance.scale = Vector3.ONE * scale_factor

	# Apply offset
	model_instance.position = data.model_offset

	# Position model container at player feet
	model_container.position = Vector3(0, 0.6, 0)

	add_child(model_container)
	print("[Player] ✓ Model loaded: %s (scale: %f)" % [data.model_path, scale_factor])

func _get_model_aabb(node: Node) -> AABB:
	var aabb = AABB()
	var first = true

	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_aabb = child.get_aabb()
			if first:
				aabb = mesh_aabb
				first = false
			else:
				aabb = aabb.merge(mesh_aabb)

		# Recursive check
		var child_aabb = _get_model_aabb(child)
		if child_aabb.size.length() > 0:
			if first:
				aabb = child_aabb
				first = false
			else:
				aabb = aabb.merge(child_aabb)

	return aabb

func _create_ability_from_data(data: AbilityData) -> Ability:
	if data.script_path == "":
		return null
	
	var script = load(data.script_path)
	if script == null:
		return null
	
	var ability = script.new()
	ability.ability_name = data.ability_name
	ability.cooldown = data.cooldown
	
	return ability

func spawn(position: Vector3):
	print("[Player] Spawning at position %s (is_local: %s)" % [position, is_local_player])
	global_position = position

	# Create visual representation
	_ensure_visual_representation()

	player_spawned.emit()
	print("[Player] ✓ Player spawned at %s" % position)

func _ensure_visual_representation():
	# Check if we already have a visual mesh
	var has_visual = false
	for child in get_children():
		if child is MeshInstance3D or child.name == "Model":
			has_visual = true
			break

	if has_visual:
		print("[Player] Visual representation already exists")
		return

	print("[Player] Creating default visual representation...")

	# Create a character mesh
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "PlayerMesh"

	# Create capsule mesh for player body
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.radius = 0.4
	capsule_mesh.height = 1.2
	mesh_instance.mesh = capsule_mesh

	# Create material based on character or local/remote status
	var material = StandardMaterial3D.new()

	if character_data and character_data.color:
		# Use character color
		material.albedo_color = character_data.color
		print("[Player] Using character color: %s" % character_data.color)
	elif is_local_player:
		material.albedo_color = Color(0.2, 0.8, 0.2)  # Green for local player
		print("[Player] Using local player color (green)")
	else:
		material.albedo_color = Color(0.8, 0.2, 0.2)  # Red for remote players
		print("[Player] Using remote player color (red)")

	mesh_instance.set_surface_override_material(0, material)

	# Position mesh so center is at player position
	mesh_instance.position = Vector3(0, 0.6, 0)

	add_child(mesh_instance)
	print("[Player] ✓ Default mesh created")
