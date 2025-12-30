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
	
	# Load character model
	if data.model_path != "":
		var model_scene = load(data.model_path)
		if model_scene:
			var model_instance = model_scene.instantiate()
			add_child(model_instance)
	
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
	print("[Player] Spawning at position %s" % position)
	global_position = position
	
	# Create a simple visual representation if no model is loaded
	if get_child_count() == 0:
		print("[Player] No visual representation, creating default mesh...")
		var mesh_instance = MeshInstance3D.new()
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 0.5
		sphere_mesh.height = 1.0
		mesh_instance.mesh = sphere_mesh
		
		# Create material
		var material = StandardMaterial3D.new()
		if is_local_player:
			material.albedo_color = Color(0.2, 0.8, 0.2)  # Green for local player
		else:
			material.albedo_color = Color(0.8, 0.2, 0.2)  # Red for remote players
		mesh_instance.set_surface_override_material(0, material)
		
		add_child(mesh_instance)
		print("[Player] ✓ Default mesh created")
	
	player_spawned.emit()
	print("[Player] ✓ Player spawned at %s" % position)
