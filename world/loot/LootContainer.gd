## Loot container that can be opened to reveal items
extends StaticBody3D
class_name LootContainer

signal container_opened(container: LootContainer, player: Player)
signal container_destroyed(container: LootContainer)

enum ContainerType {
	CRATE,
	CHEST,
	BARREL,
	SUPPLY_DROP
}

@export var container_type: ContainerType = ContainerType.CRATE
@export var health: float = 50.0
@export var loot_count: int = 2  # Number of items to drop
@export var guaranteed_health: bool = true  # Always drop at least one health item

const INTERACT_RANGE: float = 2.5
const INTERACT_COLLISION_LAYER: int = 8  # Layer 4 for interactive objects

var is_opened: bool = false
var mesh_instance: MeshInstance3D = null
var interact_prompt: Label3D = null
var is_opening: bool = false  # Prevents double-opening during animation

# Possible loot weights
var loot_weights: Dictionary = {
	LootItem.ItemType.HEALTH: 40,
	LootItem.ItemType.AMMO: 30,
	LootItem.ItemType.WEAPON: 10,
	LootItem.ItemType.ABILITY_BOOST: 15,
	LootItem.ItemType.SHIELD: 5
}

func _ready():
	add_to_group("loot_containers")
	_create_visual()
	_create_collision()

func _create_visual():
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "ContainerMesh"

	var mesh: Mesh
	var material = StandardMaterial3D.new()

	match container_type:
		ContainerType.CRATE:
			mesh = BoxMesh.new()
			mesh.size = Vector3(0.8, 0.8, 0.8)
			material.albedo_color = Color(0.6, 0.45, 0.25)  # Wood brown
		ContainerType.CHEST:
			mesh = BoxMesh.new()
			mesh.size = Vector3(1.0, 0.6, 0.6)
			material.albedo_color = Color(0.5, 0.35, 0.2)
			material.metallic = 0.3
		ContainerType.BARREL:
			mesh = CylinderMesh.new()
			mesh.top_radius = 0.35
			mesh.bottom_radius = 0.4
			mesh.height = 0.9
			material.albedo_color = Color(0.4, 0.3, 0.2)
		ContainerType.SUPPLY_DROP:
			mesh = BoxMesh.new()
			mesh.size = Vector3(1.2, 0.8, 0.8)
			material.albedo_color = Color(0.2, 0.5, 0.2)  # Military green
			material.metallic = 0.5
			# Add glow for supply drops
			material.emission_enabled = true
			material.emission = Color(0.1, 0.3, 0.1)
			material.emission_energy_multiplier = 0.3

	mesh_instance.mesh = mesh
	mesh_instance.set_surface_override_material(0, material)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh_instance.position = Vector3(0, 0.4, 0)

	add_child(mesh_instance)

func _create_collision():
	var collision = CollisionShape3D.new()
	collision.name = "ContainerCollision"

	var shape: Shape3D
	match container_type:
		ContainerType.CRATE, ContainerType.CHEST, ContainerType.SUPPLY_DROP:
			shape = BoxShape3D.new()
			shape.size = Vector3(0.8, 0.8, 0.8)
		ContainerType.BARREL:
			shape = CylinderShape3D.new()
			shape.radius = 0.4
			shape.height = 0.9

	collision.shape = shape
	collision.position = Vector3(0, 0.4, 0)
	add_child(collision)

	# Set collision layer for interact detection
	collision_layer = INTERACT_COLLISION_LAYER
	collision_mask = 2  # Can interact with player layer

func _process(_delta: float):
	_update_interact_prompt()

func _update_interact_prompt():
	if is_opened or is_opening:
		if interact_prompt:
			interact_prompt.queue_free()
			interact_prompt = null
		return

	# Find local player
	var local_player: Player = null
	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p is Player and p.is_local_player:
			local_player = p
			break

	if not local_player:
		if interact_prompt and interact_prompt.visible:
			interact_prompt.visible = false
		return

	var dist = global_position.distance_to(local_player.global_position)

	if dist <= INTERACT_RANGE:
		if not interact_prompt:
			_create_interact_prompt()
		interact_prompt.visible = true
	elif interact_prompt:
		interact_prompt.visible = false

func _create_interact_prompt():
	interact_prompt = Label3D.new()
	interact_prompt.text = "[E] Open"
	interact_prompt.position = Vector3(0, 1.2, 0)
	interact_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	interact_prompt.font_size = 48
	interact_prompt.outline_size = 8
	interact_prompt.modulate = Color(1, 1, 0.8)
	interact_prompt.no_depth_test = true
	add_child(interact_prompt)

func take_damage(amount: float, source = null):
	if is_opened or is_opening:
		return

	health -= amount
	_play_hit_effect()

	if health <= 0:
		open(source as Player if source is Player else null)

## Called when player presses interact key (E) near container
func interact(player: Player = null):
	if is_opened or is_opening:
		return

	# Check distance if player provided
	if player:
		var dist = global_position.distance_to(player.global_position)
		if dist > INTERACT_RANGE:
			print("[LootContainer] Player too far to interact (%.1f > %.1f)" % [dist, INTERACT_RANGE])
			return

	print("[LootContainer] Player interacting with container")
	is_opening = true

	# Hide prompt immediately
	if interact_prompt:
		interact_prompt.visible = false

	_play_open_animation()

func _play_open_animation():
	var tween = create_tween()

	# Jump animation
	var original_pos = mesh_instance.position
	tween.tween_property(mesh_instance, "position:y", original_pos.y + 0.4, 0.15)
	tween.set_ease(Tween.EASE_OUT)

	# Add glow effect
	var material = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	if material:
		material = material.duplicate()
		mesh_instance.set_surface_override_material(0, material)
		material.emission_enabled = true
		material.emission = Color(1, 0.9, 0.5)
		tween.parallel().tween_property(material, "emission_energy_multiplier", 2.0, 0.2)

	# Scale up slightly
	tween.parallel().tween_property(mesh_instance, "scale", Vector3(1.1, 1.1, 1.1), 0.15)

	# Fall back down
	tween.tween_property(mesh_instance, "position:y", original_pos.y, 0.1)
	tween.tween_property(mesh_instance, "scale", Vector3.ONE, 0.1)

	# Open after animation
	tween.tween_callback(func(): open(null))

func open(player: Player = null):
	if is_opened:
		return

	is_opened = true
	container_opened.emit(self, player)

	# Spawn loot
	_spawn_loot()

	# Play destruction effect
	_play_destroy_effect()

	# Remove container
	container_destroyed.emit(self)
	queue_free()

func _spawn_loot():
	var items_to_spawn: Array[LootItem.ItemType] = []

	# Guarantee health item if enabled
	if guaranteed_health:
		items_to_spawn.append(LootItem.ItemType.HEALTH)

	# Roll for remaining items
	var remaining = loot_count - items_to_spawn.size()
	for i in range(remaining):
		var item_type = _roll_loot_type()
		items_to_spawn.append(item_type)

	# Spawn items around container
	for i in range(items_to_spawn.size()):
		var angle = (TAU / items_to_spawn.size()) * i + randf() * 0.5
		var distance = 0.8 + randf() * 0.5
		var spawn_offset = Vector3(cos(angle) * distance, 0.5, sin(angle) * distance)

		_spawn_loot_item(items_to_spawn[i], global_position + spawn_offset)

func _roll_loot_type() -> LootItem.ItemType:
	var total_weight = 0
	for weight in loot_weights.values():
		total_weight += weight

	var roll = randi() % total_weight
	var current = 0

	for item_type in loot_weights:
		current += loot_weights[item_type]
		if roll < current:
			return item_type

	return LootItem.ItemType.HEALTH

func _spawn_loot_item(item_type: LootItem.ItemType, spawn_pos: Vector3):
	var item = LootItem.new()
	item.item_type = item_type
	item.position = spawn_pos

	# Set item properties based on type
	match item_type:
		LootItem.ItemType.HEALTH:
			item.item_name = "Health Pack"
			item.item_value = 25.0
		LootItem.ItemType.AMMO:
			item.item_name = "Ammo Box"
			item.item_value = 30.0
		LootItem.ItemType.WEAPON:
			item.item_name = "Weapon"
			item.item_value = 1.0
		LootItem.ItemType.ABILITY_BOOST:
			item.item_name = "Ability Boost"
			item.item_value = 0.5
		LootItem.ItemType.SHIELD:
			item.item_name = "Shield"
			item.item_value = 30.0

	# Add to scene
	var parent = get_parent()
	if parent:
		parent.add_child(item)
	else:
		get_tree().current_scene.add_child(item)

	print("[LootContainer] Spawned %s at %s" % [item.item_name, spawn_pos])

func _play_hit_effect():
	# Simple shake effect
	var original_pos = mesh_instance.position
	var tween = create_tween()
	tween.tween_property(mesh_instance, "position", original_pos + Vector3(0.05, 0, 0), 0.05)
	tween.tween_property(mesh_instance, "position", original_pos - Vector3(0.05, 0, 0), 0.05)
	tween.tween_property(mesh_instance, "position", original_pos, 0.05)

func _play_destroy_effect():
	# Create destruction particles
	var particles = GPUParticles3D.new()
	particles.amount = 20
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 0.9

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(0.3, 0.3, 0.3)
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0, -15, 0)
	mat.scale_min = 0.1
	mat.scale_max = 0.25

	# Color based on container type
	match container_type:
		ContainerType.CRATE, ContainerType.CHEST, ContainerType.BARREL:
			mat.color = Color(0.6, 0.45, 0.25)  # Wood
		ContainerType.SUPPLY_DROP:
			mat.color = Color(0.3, 0.5, 0.3)  # Metal green

	particles.process_material = mat

	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.1, 0.1, 0.1)
	particles.draw_pass_1 = mesh

	particles.position = mesh_instance.global_position
	get_tree().current_scene.add_child(particles)

	# Auto cleanup
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()
