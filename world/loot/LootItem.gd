## Loot item that can be picked up
extends Area3D
class_name LootItem

signal item_picked_up(item: LootItem, player: Player)

enum ItemType {
	HEALTH,
	AMMO,
	WEAPON,
	ABILITY_BOOST,
	SHIELD
}

@export var item_type: ItemType = ItemType.HEALTH
@export var item_name: String = "Item"
@export var item_value: float = 25.0  # Health amount, damage boost, etc.
@export var respawn_time: float = 30.0  # 0 = no respawn

# The actual ItemData instance to give to player (for WEAPON, AMMO types)
var item_data: ItemData = null

var is_active: bool = true
var mesh_instance: MeshInstance3D = null
var original_position: Vector3 = Vector3.ZERO

# Bobbing animation
var bob_time: float = 0.0
var bob_height: float = 0.2
var bob_speed: float = 2.0
var rotation_speed: float = 1.0

func _ready():
	add_to_group("loot_items")
	original_position = position

	_create_visual()
	_create_collision()

	# Connect signal for pickup
	body_entered.connect(_on_body_entered)

func _process(delta: float):
	if not is_active:
		return

	# Bobbing animation
	bob_time += delta * bob_speed
	if mesh_instance:
		mesh_instance.position.y = sin(bob_time) * bob_height
		mesh_instance.rotation.y += delta * rotation_speed

func _create_visual():
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "ItemMesh"

	var mesh: Mesh
	var material = StandardMaterial3D.new()
	material.emission_enabled = true

	match item_type:
		ItemType.HEALTH:
			mesh = SphereMesh.new()
			mesh.radius = 0.25
			mesh.height = 0.5
			material.albedo_color = Color(0.2, 0.9, 0.3)
			material.emission = Color(0.1, 0.5, 0.15)
		ItemType.AMMO:
			mesh = BoxMesh.new()
			mesh.size = Vector3(0.3, 0.2, 0.4)
			material.albedo_color = Color(0.9, 0.7, 0.2)
			material.emission = Color(0.5, 0.35, 0.1)
		ItemType.WEAPON:
			mesh = CylinderMesh.new()
			mesh.top_radius = 0.1
			mesh.bottom_radius = 0.15
			mesh.height = 0.5
			material.albedo_color = Color(0.7, 0.7, 0.8)
			material.emission = Color(0.3, 0.3, 0.4)
			material.metallic = 0.8
		ItemType.ABILITY_BOOST:
			mesh = PrismMesh.new()
			mesh.size = Vector3(0.4, 0.4, 0.4)
			material.albedo_color = Color(0.8, 0.3, 0.9)
			material.emission = Color(0.4, 0.15, 0.45)
		ItemType.SHIELD:
			mesh = TorusMesh.new()
			mesh.inner_radius = 0.15
			mesh.outer_radius = 0.3
			material.albedo_color = Color(0.3, 0.6, 0.9)
			material.emission = Color(0.15, 0.3, 0.45)

	material.emission_energy_multiplier = 0.5
	mesh_instance.mesh = mesh
	mesh_instance.set_surface_override_material(0, material)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(mesh_instance)

func _create_collision():
	var collision = CollisionShape3D.new()
	collision.name = "PickupArea"
	var shape = SphereShape3D.new()
	shape.radius = 0.8  # Pickup radius
	collision.shape = shape
	add_child(collision)

	# Set collision layer for items
	collision_layer = 4  # Layer 3 for items
	collision_mask = 2   # Detect players (layer 2)

func _on_body_entered(body: Node3D):
	if not is_active:
		return

	if body is Player:
		_pickup(body as Player)

func _pickup(player: Player):
	is_active = false
	item_picked_up.emit(self, player)

	# Apply item effect
	_apply_effect(player)

	# Visual feedback
	_play_pickup_effect()

	# Handle respawn or removal
	if respawn_time > 0:
		_start_respawn_timer()
	else:
		queue_free()

func _apply_effect(player: Player):
	match item_type:
		ItemType.HEALTH:
			var health = player.get_component("HealthComponent")
			if health:
				health.heal(item_value)
				print("[LootItem] Healed player for %f" % item_value)
		ItemType.AMMO:
			var inventory = player.get_component("InventoryComponent")
			if inventory:
				# If item_data is set, use it. Otherwise create a default AmmoItem
				var ammo_item = item_data if item_data is AmmoItem else _create_default_ammo()
				if inventory.add_item(ammo_item):
					print("[LootItem] Added %s to inventory" % ammo_item.item_name)
				else:
					print("[LootItem] Inventory full, cannot add ammo")
		ItemType.WEAPON:
			var inventory = player.get_component("InventoryComponent")
			if inventory:
				# If item_data is set, use it. Otherwise create a default weapon
				var weapon_item = item_data if item_data is Weapon else _create_default_weapon()
				if inventory.add_item(weapon_item):
					print("[LootItem] Added %s to inventory" % weapon_item.item_name)
				else:
					print("[LootItem] Inventory full, cannot add weapon")
		ItemType.ABILITY_BOOST:
			# Temporary ability cooldown reduction
			var ability = player.get_component("AbilityComponent")
			if ability:
				# Reduce all cooldowns
				print("[LootItem] Ability boost pickup")
		ItemType.SHIELD:
			var health = player.get_component("HealthComponent")
			if health and health.has_method("add_shield"):
				health.add_shield(item_value)
			print("[LootItem] Shield pickup (value: %f)" % item_value)

func _play_pickup_effect():
	# Hide mesh
	if mesh_instance:
		mesh_instance.visible = false

	# Create pickup particles
	var particles = GPUParticles3D.new()
	particles.amount = 15
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.explosiveness = 1.0

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.3
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, -5, 0)
	mat.scale_min = 0.1
	mat.scale_max = 0.2

	# Color based on item type
	match item_type:
		ItemType.HEALTH:
			mat.color = Color(0.2, 1.0, 0.3)
		ItemType.AMMO:
			mat.color = Color(1.0, 0.8, 0.2)
		ItemType.WEAPON:
			mat.color = Color(0.8, 0.8, 0.9)
		ItemType.ABILITY_BOOST:
			mat.color = Color(0.9, 0.3, 1.0)
		ItemType.SHIELD:
			mat.color = Color(0.3, 0.7, 1.0)

	particles.process_material = mat

	var mesh = SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	particles.draw_pass_1 = mesh

	add_child(particles)

func _start_respawn_timer():
	await get_tree().create_timer(respawn_time).timeout
	_respawn()

func _respawn():
	is_active = true
	if mesh_instance:
		mesh_instance.visible = true
	position = original_position
	print("[LootItem] %s respawned" % item_name)

## Create default ammo based on item_value (used as ammo type)
func _create_default_ammo() -> AmmoItem:
	var ammo_type = int(item_value) % 3 as AmmoItem.AmmoType  # Use item_value as type hint
	var ammo = AmmoItem.new(ammo_type, 30)
	return ammo

## Create default weapon (pistol)
func _create_default_weapon() -> RangedWeapon:
	var weapon = RangedWeapon.new()
	weapon.item_name = "Pistol"
	weapon.ammo_type = AmmoItem.AmmoType.PISTOL
	weapon.current_ammo = 12
	weapon.magazine_size = 12
	weapon.reload_time = 2.0
	return weapon
