## Player entity with all components
extends "res://core/entities/Entity.gd"
class_name Player

signal player_ready
signal player_spawned

var player_name: String = ""
var character_data: CharacterData = null
var is_local_player: bool = false
## What the hero wears: {"skin", "hat", "weapon"} (Cosmetics ids). Our own from PlayerProfile,
## others' from the server (lobby -> ServerPlayer -> player state "cosmetics")
var cosmetics: Dictionary = {}

func _ready():
	super._ready()
	add_to_group("players")
	add_to_group("entities")

	# Initialize components
	_initialize_components()

	var health = get_component("HealthComponent")
	if health:
		health.died.connect(_on_died)
		# Floating numbers: hits and real heals (regeneration ticks are too small to show)
		health.damage_taken.connect(func(amount, _source): AbilityFX.number(self, -amount, Color(1.0, 0.42, 0.35)))
		var born = Time.get_ticks_msec()
		health.healed.connect(func(amount):
			# not the max-health bonus of a passive while the hero is being set up
			if amount >= 4.0 and Time.get_ticks_msec() - born > 1500:
				AbilityFX.number(self, amount, Color(0.45, 1.0, 0.5)))

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

	# Stun, slow, blind, stealth, knockback from abilities
	var status = StatusComponent.new(self)
	add_component(status)

## Falling off the map (destroyed or edge tiles) eliminates you
const KILL_HEIGHT: float = -15.0

func _physics_process(delta: float):
	super._physics_process(delta)
	if is_local_player:
		# Tree canopies open up around you (tree_canopy.gdshader)
		RenderingServer.global_shader_parameter_set("hero_position", global_position)
	if global_position.y < KILL_HEIGHT:
		var health = get_component("HealthComponent")
		# Only the authority decides deaths; clients learn it through the synced health
		if health and not health.is_dead and _is_authority():
			health.die()

func _is_authority() -> bool:
	var mp = get_tree().get_multiplayer()
	return not mp.has_multiplayer_peer() or mp.is_server()

func _on_died():
	var movement = get_component("MovementComponent")
	if movement:
		movement.stop()
		movement.enabled = false
	# No shooting or abilities from beyond the grave (they're invisible and unhittable)
	for component_name in ["CombatComponent", "AbilityComponent"]:
		var component = get_component(component_name)
		if component:
			component.enabled = false
	# Stop colliding with bullets and players
	collision_layer = 0
	var model = get_node_or_null("Model")
	var target = model if model else self
	var tween = create_tween()
	tween.tween_property(target, "scale", Vector3(1.3, 0.05, 1.3), 0.25).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func(): visible = false)

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

	if is_local_player and cosmetics.is_empty():
		cosmetics = PlayerProfile.equipped_for(data.character_name)
	_apply_cosmetics()

## Put on a skin / hat / weapon finish (the server tells us what the others wear)
func apply_cosmetics(wear: Dictionary) -> void:
	cosmetics = wear.duplicate()
	_apply_cosmetics()

func _apply_cosmetics() -> void:
	var mesh = find_child("ModelMesh", true, false) as Node3D
	if mesh:
		Cosmetics.apply_to_character(mesh, String(cosmetics.get("skin", "classic")), String(cosmetics.get("hat", "no_hat")))
	var weapon_visual = get_node_or_null("WeaponVisual")
	if weapon_visual:
		weapon_visual.refresh()

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
	ModelUtils.apply_lowpoly_look(model_instance)
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

	# Older models have their origin at the body center, generated ones at the feet
	model_container.position = Vector3(0, 0.0 if data.model_origin_at_feet else 0.6, 0)

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

	# Create weapon visual component
	_create_weapon_visual()

	# Procedural / skeletal animation of the model
	if not has_node("Animator"):
		var animator = CharacterAnimator.new()
		animator.name = "Animator"
		add_child(animator)
		animator.setup(self)
		# Drop in with an impact; the delay lets the loading curtain fade first
		animator.play_spawn(0.45)

	player_spawned.emit()
	print("[Player] ✓ Player spawned at %s" % position)

## Starting pistol + ammo. Given both to the owning client's player and to the server
## entity, so server-side hit validation uses the same weapon the client shoots with.
func give_starting_loadout():
	var inventory = get_component("InventoryComponent")
	if not inventory or inventory.get_weapon_count() > 0:
		return

	var pistol = RangedWeapon.create_weapon(RangedWeapon.WeaponType.PISTOL)
	inventory.add_weapon_to_slot(pistol)
	inventory.add_item(AmmoItem.new(AmmoItem.AmmoType.PISTOL, 60))

func _create_weapon_visual():
	# Create weapon visual for ALL players (so others can see your weapon)
	var existing = get_node_or_null("WeaponVisual")
	if existing:
		return

	var weapon_visual = WeaponVisualComponent.new()
	add_child(weapon_visual)
	weapon_visual.setup(self)
	print("[Player] ✓ Weapon visual component created (local: %s)" % is_local_player)

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
