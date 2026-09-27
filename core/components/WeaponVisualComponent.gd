## Handles visual representation of weapon in player's hands
extends Node3D
class_name WeaponVisualComponent

var player: Player = null
var current_weapon: RangedWeapon = null
var weapon_model: Node3D = null
var hand_position: Vector3 = Vector3(0.4, 0.8, -0.3)  # Right hand offset

# Weapon model cache
var loaded_models: Dictionary = {}

func _ready():
	pass

func setup(p_player: Player):
	player = p_player
	name = "WeaponVisual"

	# Connect to combat component
	var combat = player.get_component("CombatComponent")
	if combat:
		combat.weapon_changed.connect(_on_weapon_changed)
		combat.shot_fired.connect(_on_shot_fired)
		combat.reload_started.connect(_on_reload_started)
		combat.reload_finished.connect(_on_reload_finished)

		# Show current weapon if any
		if combat.equipped_ranged_weapon:
			_show_weapon(combat.equipped_ranged_weapon)
			print("[WeaponVisual] Initial weapon found: %s" % combat.equipped_ranged_weapon.item_name)

	# Also connect to inventory component for weapon slot changes
	var inventory = player.get_component("InventoryComponent")
	if inventory:
		inventory.weapon_equipped.connect(_on_weapon_equipped)
		inventory.weapon_slot_changed.connect(_on_weapon_slot_changed)
		print("[WeaponVisual] Connected to inventory signals")

func _on_weapon_changed(weapon_data):
	print("[WeaponVisual] weapon_changed signal received")
	# weapon_data might be WeaponData or RangedWeapon depending on source
	if weapon_data is RangedWeapon:
		_show_weapon(weapon_data)
	else:
		# Fallback: check combat component for equipped weapon
		var combat = player.get_component("CombatComponent") if player else null
		if combat and combat.equipped_ranged_weapon:
			_show_weapon(combat.equipped_ranged_weapon)
		else:
			_hide_weapon()

func _on_weapon_equipped(weapon: RangedWeapon, _slot: int):
	print("[WeaponVisual] weapon_equipped signal: %s in slot %d" % [weapon.item_name if weapon else "none", _slot])
	if weapon:
		_show_weapon(weapon)

func _on_weapon_slot_changed(slot: int):
	print("[WeaponVisual] weapon_slot_changed to slot %d" % slot)
	var inventory = player.get_component("InventoryComponent") if player else null
	if inventory:
		var weapon = inventory.get_weapon_in_slot(slot)
		if weapon:
			_show_weapon(weapon)
		else:
			_hide_weapon()

func _show_weapon(weapon: RangedWeapon):
	print("[WeaponVisual] _show_weapon called for: %s" % weapon.item_name)
	current_weapon = weapon

	# Remove old weapon model
	if weapon_model:
		weapon_model.queue_free()
		weapon_model = null

	# Load weapon model
	var model_path = weapon.model_path
	print("[WeaponVisual] Model path: %s" % model_path)
	print("[WeaponVisual] Model exists: %s" % ResourceLoader.exists(model_path))

	if model_path == "" or not ResourceLoader.exists(model_path):
		# Create default weapon mesh
		print("[WeaponVisual] Creating default mesh for weapon type: %d" % weapon.weapon_type)
		weapon_model = _create_default_weapon_mesh(weapon.weapon_type)
	else:
		# Load actual model
		print("[WeaponVisual] Loading GLB model: %s" % model_path)
		if loaded_models.has(model_path):
			weapon_model = loaded_models[model_path].duplicate()
		else:
			var scene = load(model_path)
			if scene:
				weapon_model = scene.instantiate()
				loaded_models[model_path] = scene.instantiate()
				print("[WeaponVisual] GLB model loaded successfully")
			else:
				print("[WeaponVisual] Failed to load GLB, using default mesh")
				weapon_model = _create_default_weapon_mesh(weapon.weapon_type)

	if weapon_model:
		add_child(weapon_model)
		_position_weapon()
		print("[WeaponVisual] Weapon model added to scene: %s" % weapon.item_name)

func _hide_weapon():
	current_weapon = null
	if weapon_model:
		weapon_model.queue_free()
		weapon_model = null

## Update weapon from external source (for network sync)
func update_weapon(weapon_name: String):
	print("[WeaponVisual] update_weapon called with: %s" % weapon_name)
	# Try to find weapon in inventory
	var inventory = player.get_component("InventoryComponent") if player else null
	if inventory:
		# Check all weapon slots for matching name
		for slot in range(3):
			var weapon = inventory.get_weapon_in_slot(slot)
			if weapon and weapon.item_name == weapon_name:
				_show_weapon(weapon)
				return

	# If not found in inventory but we need to show it, keep current
	print("[WeaponVisual] Weapon '%s' not found in inventory" % weapon_name)

func _position_weapon():
	if not weapon_model:
		return

	# Scale and offset based on weapon type
	# In Godot: -Z is forward, +X is right, +Y is up
	# Weapon is positioned to the right side of player, in front
	var scale_factor = 0.5
	var offset = Vector3(0.4, 0.8, -0.5)  # Right side (+X), chest height (+Y), in front (-Z)
	var weapon_rotation = Vector3.ZERO

	match current_weapon.weapon_type if current_weapon else RangedWeapon.WeaponType.PISTOL:
		RangedWeapon.WeaponType.PISTOL:
			scale_factor = 0.4
			offset = Vector3(0.35, 0.7, -0.4)
		RangedWeapon.WeaponType.SHOTGUN:
			scale_factor = 0.5
			offset = Vector3(0.3, 0.75, -0.6)
		RangedWeapon.WeaponType.SNIPER:
			scale_factor = 0.55
			offset = Vector3(0.25, 0.8, -0.7)
		RangedWeapon.WeaponType.RIFLE:
			scale_factor = 0.5
			offset = Vector3(0.3, 0.75, -0.6)
		RangedWeapon.WeaponType.FLAMETHROWER:
			scale_factor = 0.5
			offset = Vector3(0.35, 0.7, -0.5)

	weapon_model.position = offset
	weapon_model.scale = Vector3.ONE * scale_factor
	# Rotate weapon 180 degrees to point forward (models usually face +Z, we need -Z)
	weapon_model.rotation.y = PI

func _create_default_weapon_mesh(weapon_type: RangedWeapon.WeaponType) -> Node3D:
	var container = Node3D.new()
	container.name = "DefaultWeaponMesh"

	var mesh_instance = MeshInstance3D.new()
	var material = StandardMaterial3D.new()
	material.metallic = 0.8
	material.roughness = 0.3

	# All weapons point along -Z axis (forward in Godot)
	match weapon_type:
		RangedWeapon.WeaponType.PISTOL:
			# Small box for pistol - pointing forward
			var mesh = BoxMesh.new()
			mesh.size = Vector3(0.1, 0.15, 0.35)  # Width, Height, Length (forward)
			mesh_instance.mesh = mesh
			material.albedo_color = Color(0.2, 0.2, 0.25)

		RangedWeapon.WeaponType.SHOTGUN:
			# Long cylinder for shotgun - pointing forward (-Z)
			var mesh = CylinderMesh.new()
			mesh.top_radius = 0.04
			mesh.bottom_radius = 0.04
			mesh.height = 1.0
			mesh_instance.mesh = mesh
			# Rotate cylinder to point along Z axis (forward)
			mesh_instance.rotation.x = deg_to_rad(-90)
			material.albedo_color = Color(0.3, 0.25, 0.2)

		RangedWeapon.WeaponType.SNIPER:
			# Long thin cylinder for sniper
			var mesh = CylinderMesh.new()
			mesh.top_radius = 0.03
			mesh.bottom_radius = 0.03
			mesh.height = 1.4
			mesh_instance.mesh = mesh
			mesh_instance.rotation.x = deg_to_rad(-90)
			material.albedo_color = Color(0.15, 0.15, 0.2)

		RangedWeapon.WeaponType.RIFLE:
			# Medium cylinder for rifle
			var mesh = CylinderMesh.new()
			mesh.top_radius = 0.035
			mesh.bottom_radius = 0.035
			mesh.height = 0.9
			mesh_instance.mesh = mesh
			mesh_instance.rotation.x = deg_to_rad(-90)
			material.albedo_color = Color(0.25, 0.25, 0.25)

		RangedWeapon.WeaponType.FLAMETHROWER:
			# Box with cylinder for flamethrower
			var mesh = CylinderMesh.new()
			mesh.top_radius = 0.08
			mesh.bottom_radius = 0.06
			mesh.height = 0.8
			mesh_instance.mesh = mesh
			mesh_instance.rotation.x = deg_to_rad(-90)
			material.albedo_color = Color(0.4, 0.2, 0.1)
			material.emission_enabled = true
			material.emission = Color(0.5, 0.2, 0.05)
			material.emission_energy_multiplier = 0.3

	mesh_instance.set_surface_override_material(0, material)
	container.add_child(mesh_instance)

	return container

func _on_shot_fired(_from: Vector3, _to: Vector3, _hit: bool):
	# Weapon recoil animation - move back (+Z is backward since weapon is rotated 180)
	if weapon_model:
		var original_pos = weapon_model.position
		var original_rot = weapon_model.rotation
		var tween = create_tween()

		# Recoil: move back and rotate up slightly
		var recoil_pos = original_pos + Vector3(0, 0.02, 0.08)  # Slight up, back
		var recoil_rot = original_rot + Vector3(deg_to_rad(-8), 0, 0)  # Tilt up

		tween.tween_property(weapon_model, "position", recoil_pos, 0.04)
		tween.parallel().tween_property(weapon_model, "rotation", recoil_rot, 0.04)
		tween.tween_property(weapon_model, "position", original_pos, 0.12).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(weapon_model, "rotation", original_rot, 0.12).set_ease(Tween.EASE_OUT)

		# Muzzle flash
		_create_muzzle_flash()

func _create_muzzle_flash():
	if not weapon_model:
		return

	# Calculate muzzle position (end of weapon barrel)
	var muzzle_offset = Vector3(0, 0, -0.6)  # Forward from weapon center
	match current_weapon.weapon_type if current_weapon else RangedWeapon.WeaponType.PISTOL:
		RangedWeapon.WeaponType.PISTOL:
			muzzle_offset = Vector3(0, 0, -0.25)
		RangedWeapon.WeaponType.SHOTGUN:
			muzzle_offset = Vector3(0, 0, -0.55)
		RangedWeapon.WeaponType.SNIPER:
			muzzle_offset = Vector3(0, 0, -0.75)
		RangedWeapon.WeaponType.RIFLE:
			muzzle_offset = Vector3(0, 0, -0.5)
		RangedWeapon.WeaponType.FLAMETHROWER:
			muzzle_offset = Vector3(0, 0, -0.45)

	# Light flash
	var flash = OmniLight3D.new()
	flash.light_color = Color(1, 0.8, 0.3)
	flash.light_energy = 4.0
	flash.omni_range = 4.0
	flash.position = weapon_model.position + muzzle_offset
	add_child(flash)

	# Visual flash mesh
	var flash_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	flash_mesh.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.9, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.7, 0.3)
	mat.emission_energy_multiplier = 8.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mesh.material_override = mat
	flash_mesh.position = weapon_model.position + muzzle_offset
	flash_mesh.scale = Vector3(1.2, 1.2, 2.0)
	add_child(flash_mesh)

	# Animate flash
	var tween = create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.08)
	tween.parallel().tween_property(flash_mesh, "scale", Vector3.ONE * 0.01, 0.06)  # not 0: zero basis errors
	tween.tween_callback(flash.queue_free)
	tween.tween_callback(flash_mesh.queue_free)

func _on_reload_started():
	# Reload animation - lower and tilt weapon
	if weapon_model:
		var original_pos = weapon_model.position
		var original_rot = weapon_model.rotation

		var tween = create_tween()
		# Lower weapon and tilt it (simulating magazine removal)
		var reload_pos = original_pos + Vector3(0, -0.15, 0.1)
		var reload_rot = original_rot + Vector3(deg_to_rad(-35), deg_to_rad(-15), 0)

		tween.tween_property(weapon_model, "position", reload_pos, 0.25)
		tween.parallel().tween_property(weapon_model, "rotation", reload_rot, 0.25)

func _on_reload_finished():
	# Return weapon to normal position with snap
	if weapon_model:
		# Restore to proper position based on weapon type
		var tween = create_tween()

		# Quick snap back animation
		var final_rot = Vector3(0, PI, 0)  # Normal rotation

		# Determine final position based on weapon type
		var final_pos = Vector3(0.35, 0.7, -0.4)  # Default pistol
		if current_weapon:
			match current_weapon.weapon_type:
				RangedWeapon.WeaponType.PISTOL:
					final_pos = Vector3(0.35, 0.7, -0.4)
				RangedWeapon.WeaponType.SHOTGUN:
					final_pos = Vector3(0.3, 0.75, -0.6)
				RangedWeapon.WeaponType.SNIPER:
					final_pos = Vector3(0.25, 0.8, -0.7)
				RangedWeapon.WeaponType.RIFLE:
					final_pos = Vector3(0.3, 0.75, -0.6)
				RangedWeapon.WeaponType.FLAMETHROWER:
					final_pos = Vector3(0.35, 0.7, -0.5)

		# Slight overshoot then settle
		var overshoot_pos = final_pos + Vector3(0, 0.05, -0.05)
		tween.tween_property(weapon_model, "position", overshoot_pos, 0.15).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(weapon_model, "rotation", final_rot, 0.15).set_ease(Tween.EASE_OUT)
		tween.tween_property(weapon_model, "position", final_pos, 0.1).set_ease(Tween.EASE_IN_OUT)
