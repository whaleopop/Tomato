## Handles combat: attacks, weapons, damage dealing
## Supports both melee and hitscan ranged weapons
extends Component
class_name CombatComponent

signal attack_started
signal attack_finished
signal weapon_changed(new_weapon)
signal target_hit(target, damage: float)  # target: Entity
signal shot_fired(from: Vector3, to: Vector3, hit: bool)
signal reload_started
signal reload_finished

var current_weapon: WeaponData = null
var equipped_ranged_weapon: RangedWeapon = null  # Active ranged weapon instance
var attack_cooldown: float = 0.0
var is_attacking: bool = false
var is_reloading: bool = false
var attack_range: float = 2.0
var base_damage: float = 10.0
var ranged_damage_multiplier: float = 1.0  # Multiplier for ranged weapon damage
var reload_timer: float = 0.0

# Muzzle offset from entity position
var muzzle_offset: Vector3 = Vector3(0.5, 1.0, 0)

func _init(p_entity = null):  # p_entity: Entity
	entity = p_entity

func update(delta: float):
	if not enabled:
		return

	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	# Handle reload timer
	if is_reloading and reload_timer > 0:
		reload_timer -= delta
		if reload_timer <= 0:
			_complete_reload()

func can_attack() -> bool:
	return enabled and attack_cooldown <= 0.0 and not is_attacking and not is_reloading

func can_shoot() -> bool:
	if not can_attack():
		return false
	if equipped_ranged_weapon:
		return equipped_ranged_weapon.can_shoot()
	return current_weapon != null and current_weapon.weapon_type == "ranged"

## Perform attack - uses hitscan for ranged weapons
func attack(target_position: Vector3, target_entity = null) -> bool:  # target_entity: Entity
	if not can_attack():
		return false

	is_attacking = true
	attack_started.emit()

	var damage = base_damage

	# NEW: Check for equipped ranged weapon first (new weapon system)
	if equipped_ranged_weapon:
		damage = equipped_ranged_weapon.damage * ranged_damage_multiplier
		var success = _perform_hitscan_attack(target_position, damage)
		is_attacking = false
		attack_finished.emit()
		return success

	# Legacy: Check for current_weapon (old WeaponData system)
	if current_weapon:
		damage = current_weapon.damage
		attack_range = current_weapon.range
		attack_cooldown = current_weapon.cooldown

		# Apply ranged damage multiplier for ranged weapons
		if current_weapon.weapon_type == "ranged":
			damage *= ranged_damage_multiplier
			# Use hitscan for ranged weapons
			var success = _perform_hitscan_attack(target_position, damage)
			is_attacking = false
			attack_finished.emit()
			return success
	else:
		attack_cooldown = 0.5  # Default cooldown

	# Melee attack - check if target is in range
	if target_entity:
		var distance = entity.global_position.distance_to(target_entity.global_position)
		if distance > attack_range:
			is_attacking = false
			attack_finished.emit()
			return false

		# Deal damage to target
		var health_component = target_entity.get_component("HealthComponent")
		if health_component:
			var actual_damage = health_component.take_damage(damage, entity)
			target_hit.emit(target_entity, actual_damage)

	# Finish attack after cooldown
	if entity and is_instance_valid(entity):
		await entity.get_tree().create_timer(attack_cooldown).timeout
	is_attacking = false
	attack_finished.emit()

	return true

## Perform hitscan ranged attack
func _perform_hitscan_attack(target_position: Vector3, damage: float) -> bool:
	if not entity or not is_instance_valid(entity):
		print("[CombatComponent] ERROR: entity invalid")
		return false

	# Check and consume ammo
	if equipped_ranged_weapon:
		if not equipped_ranged_weapon.consume_ammo():
			# Out of ammo - start reload
			print("[CombatComponent] Out of ammo - starting reload")
			start_reload()
			return false

	var muzzle_pos = _get_muzzle_position()
	var direction = (target_position - muzzle_pos).normalized()

	# Get world for raycast
	var viewport = entity.get_viewport()
	if not viewport:
		return false

	var world_3d = viewport.world_3d
	if not world_3d:
		return false

	# Determine weapon type for effects
	var weapon_type = RangedWeapon.WeaponType.PISTOL
	if equipped_ranged_weapon:
		weapon_type = equipped_ranged_weapon.weapon_type
		damage = equipped_ranged_weapon.damage * ranged_damage_multiplier
		attack_range = equipped_ranged_weapon.range
		attack_cooldown = equipped_ranged_weapon.fire_rate
	elif current_weapon:
		if current_weapon.weapon_name.to_lower().contains("shotgun"):
			weapon_type = RangedWeapon.WeaponType.SHOTGUN
		elif current_weapon.weapon_name.to_lower().contains("sniper"):
			weapon_type = RangedWeapon.WeaponType.SNIPER
		elif current_weapon.weapon_name.to_lower().contains("rifle"):
			weapon_type = RangedWeapon.WeaponType.RIFLE
		elif current_weapon.weapon_name.to_lower().contains("flame"):
			weapon_type = RangedWeapon.WeaponType.FLAMETHROWER

	var hit_result: Dictionary
	var hit_results: Array[Dictionary] = []
	var end_pos = target_position

	# CRITICAL: Apply damage ONLY on server to prevent double-damage bug
	var is_server = entity.get_tree().get_multiplayer().is_server()

	# Perform appropriate shot type
	match weapon_type:
		RangedWeapon.WeaponType.SHOTGUN:
			var pellet_count = 8
			var spread = 25.0
			if equipped_ranged_weapon:
				pellet_count = equipped_ranged_weapon.pellet_count
				spread = equipped_ranged_weapon.spread_angle

			hit_results = HitscanSystem.shoot_spread(
				world_3d, muzzle_pos, direction,
				pellet_count, spread, attack_range, damage, entity
			)
			for result in hit_results:
				if result.get("hit", false) and is_server:
					var actual_dmg = HitscanSystem.apply_hit_damage(result, entity)
					if actual_dmg > 0:
						target_hit.emit(result.get("collider"), actual_dmg)
			_create_shot_effects_shotgun(muzzle_pos, hit_results)
			shot_fired.emit(muzzle_pos, target_position, hit_results.size() > 0)

		RangedWeapon.WeaponType.SNIPER:
			hit_results = HitscanSystem.shoot_penetrating(
				world_3d, muzzle_pos, direction,
				attack_range, damage, 2, 0.6, entity
			)
			for result in hit_results:
				if result.get("hit", false) and is_server:
					var actual_dmg = HitscanSystem.apply_hit_damage(result, entity)
					if actual_dmg > 0:
						target_hit.emit(result.get("collider"), actual_dmg)
			if hit_results.size() > 0:
				end_pos = hit_results[-1].get("position", target_position)
				_create_shot_effects(muzzle_pos, hit_results[0], "sniper")
			shot_fired.emit(muzzle_pos, end_pos, hit_results.size() > 0)

		RangedWeapon.WeaponType.FLAMETHROWER:
			# Flamethrower - cone of fire with burn effect
			_perform_flamethrower_attack(muzzle_pos, direction, damage)
			shot_fired.emit(muzzle_pos, muzzle_pos + direction * attack_range, true)

		RangedWeapon.WeaponType.RIFLE:
			# Rifle - fast single shots with slight spread
			var accuracy = 0.85
			if equipped_ranged_weapon:
				accuracy = equipped_ranged_weapon.accuracy
			var spread_dir = _apply_accuracy(direction, accuracy)
			hit_result = HitscanSystem.shoot(
				world_3d, muzzle_pos, spread_dir,
				attack_range, damage, entity
			)
			if hit_result.get("hit", false) and is_server:
				var actual_dmg = HitscanSystem.apply_hit_damage(hit_result, entity)
				if actual_dmg > 0:
					target_hit.emit(hit_result.get("collider"), actual_dmg)
			end_pos = hit_result.get("position", muzzle_pos + direction * attack_range)
			_create_shot_effects(muzzle_pos, hit_result, "rifle")
			shot_fired.emit(muzzle_pos, end_pos, hit_result.get("hit", false))

		_:  # PISTOL and default
			var accuracy = 0.95
			if equipped_ranged_weapon:
				accuracy = equipped_ranged_weapon.accuracy
			var spread_dir = _apply_accuracy(direction, accuracy)
			hit_result = HitscanSystem.shoot(
				world_3d, muzzle_pos, spread_dir,
				attack_range, damage, entity
			)
			if hit_result.get("hit", false) and is_server:
				var actual_dmg = HitscanSystem.apply_hit_damage(hit_result, entity)
				if actual_dmg > 0:
					target_hit.emit(hit_result.get("collider"), actual_dmg)
			end_pos = hit_result.get("position", muzzle_pos + direction * attack_range)
			_create_shot_effects(muzzle_pos, hit_result, "pistol")
			shot_fired.emit(muzzle_pos, end_pos, hit_result.get("hit", false))

	# Add bullet trail to visibility system
	_add_visibility_trail(muzzle_pos, end_pos)

	# Camera shake for feedback
	if ScreenEffects.instance:
		var shake_intensity = 0.1
		if weapon_type == RangedWeapon.WeaponType.SNIPER:
			shake_intensity = 0.3
		elif weapon_type == RangedWeapon.WeaponType.SHOTGUN:
			shake_intensity = 0.25
		ScreenEffects.shake(shake_intensity, 8.0)

	# Sync shot to network for all clients to see visual effects
	if entity and "entity_id" in entity:
		var tree = entity.get_tree()
		if tree and tree.get_multiplayer().has_multiplayer_peer():
			var hit_target_id = -1
			if hit_result and hit_result.get("hit", false):
				var collider = hit_result.get("collider")
				if collider and "entity_id" in collider:
					hit_target_id = collider.entity_id

			# Determine weapon type string
			var weapon_type_str = "pistol"
			match weapon_type:
				RangedWeapon.WeaponType.SHOTGUN:
					weapon_type_str = "shotgun"
				RangedWeapon.WeaponType.SNIPER:
					weapon_type_str = "sniper"
				RangedWeapon.WeaponType.RIFLE:
					weapon_type_str = "rifle"

			# Only send RPC if we're the authority (local player or server)
			if entity.has_method("is_local_player") and entity.is_local_player:
				var combat_sync = tree.root.get_node_or_null("/root/NetworkCombatSync")
				if combat_sync:
					combat_sync.sync_shot_fired.rpc(entity.entity_id, muzzle_pos, end_pos, weapon_type_str, hit_result.get("hit", false), hit_target_id)

	return true

## Apply accuracy spread to direction
func _apply_accuracy(direction: Vector3, accuracy: float) -> Vector3:
	if accuracy >= 1.0:
		return direction

	var spread = (1.0 - accuracy) * 0.15
	var random_spread = Vector3(
		randf_range(-spread, spread),
		randf_range(-spread, spread),
		randf_range(-spread, spread)
	)
	return (direction + random_spread).normalized()

## Perform flamethrower attack
func _perform_flamethrower_attack(muzzle_pos: Vector3, direction: Vector3, damage: float):
	if not entity or not is_instance_valid(entity):
		return

	if not entity.is_inside_tree():
		return

	var parent = entity.get_parent()
	if not parent:
		parent = entity.get_tree().current_scene

	var burn_dmg = 5.0
	var burn_dur = 3.0
	if equipped_ranged_weapon:
		burn_dmg = equipped_ranged_weapon.burn_damage
		burn_dur = equipped_ranged_weapon.burn_duration

	# Create flame particles
	_create_flame_effect(muzzle_pos, direction)

	# CRITICAL: Apply damage ONLY on server
	var is_server = entity.get_tree().get_multiplayer().is_server()
	if not is_server:
		return

	# Damage in cone
	var players = entity.get_tree().get_nodes_in_group("players")
	for player in players:
		if player == entity:
			continue
		if not is_instance_valid(player):
			continue

		var to_player = player.global_position - muzzle_pos
		var dist = to_player.length()

		if dist > attack_range:
			continue

		# Check cone angle
		var angle = direction.angle_to(to_player.normalized())
		if angle > deg_to_rad(30):  # 30 degree cone
			continue

		# Apply damage
		var health = player.get_component("HealthComponent")
		if health:
			health.take_damage(damage, entity)
			target_hit.emit(player, damage)

	# Leave fire trail if enabled
	if equipped_ranged_weapon and equipped_ranged_weapon.fire_trail_enabled:
		var fire_pos = muzzle_pos + direction * attack_range * 0.7
		fire_pos.y = 0.1  # Ground level
		FireEffect.create_at(fire_pos, parent, burn_dmg, burn_dur, 1.5)

## Create flame visual effect
func _create_flame_effect(muzzle_pos: Vector3, direction: Vector3):
	if not entity or not is_instance_valid(entity):
		return

	if not entity.is_inside_tree():
		return

	var parent = entity.get_parent()
	if not parent:
		return

	var particles = GPUParticles3D.new()
	particles.amount = 50
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.explosiveness = 0.8

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = direction
	mat.spread = 20.0
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 25.0
	mat.gravity = Vector3(0, 2, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.8

	var gradient = GradientTexture1D.new()
	var grad = Gradient.new()
	grad.add_point(0.0, Color(1.0, 0.9, 0.3, 1.0))
	grad.add_point(0.3, Color(1.0, 0.5, 0.1, 0.9))
	grad.add_point(0.7, Color(0.8, 0.2, 0.05, 0.5))
	grad.add_point(1.0, Color(0.2, 0.1, 0.1, 0.0))
	gradient.gradient = grad
	mat.color_ramp = gradient

	particles.process_material = mat
	particles.draw_pass_1 = SphereMesh.new()

	particles.global_position = muzzle_pos
	parent.add_child(particles)

	# Light
	var light = OmniLight3D.new()
	light.light_color = Color(1, 0.6, 0.2)
	light.light_energy = 3.0
	light.omni_range = 8.0
	parent.add_child(light)
	light.global_position = muzzle_pos + direction * 2

	# Cleanup
	var tween = parent.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.3)
	tween.tween_callback(light.queue_free)
	particles.finished.connect(particles.queue_free)

## Add bullet trail to visibility system
func _add_visibility_trail(start: Vector3, end: Vector3):
	var vis_system = entity.get_tree().get_first_node_in_group("visibility_system") as VisibilitySystem
	if vis_system:
		var duration = 0.5
		if equipped_ranged_weapon:
			duration = equipped_ranged_weapon.bullet_visibility_duration
		vis_system.add_bullet_trail(start, end, duration)

## Get muzzle position in world space
func _get_muzzle_position() -> Vector3:
	if not entity:
		return Vector3.ZERO

	# Calculate muzzle position based on entity rotation
	var forward = -entity.transform.basis.z
	var right = entity.transform.basis.x
	var offset = right * muzzle_offset.x + Vector3.UP * muzzle_offset.y + forward * muzzle_offset.z

	return entity.global_position + offset

## Create visual effects for shot
func _create_shot_effects(muzzle_pos: Vector3, hit_result: Dictionary, weapon_type: String) -> void:
	if not entity or not is_instance_valid(entity):
		return

	var parent = _effects_parent()
	var hit_pos = hit_result.get("position", muzzle_pos + (entity.global_position - muzzle_pos).normalized() * 50)
	var hit_normal = hit_result.get("normal", Vector3.UP)
	var collider = hit_result.get("collider")

	WeaponEffects.create_shot_effects(parent, muzzle_pos, hit_pos, hit_normal, collider, weapon_type)

## Create visual effects for shotgun spread
func _create_shot_effects_shotgun(muzzle_pos: Vector3, results: Array[Dictionary]) -> void:
	if not entity or not is_instance_valid(entity):
		return

	WeaponEffects.create_shotgun_effects(_effects_parent(), muzzle_pos, results)

## Shot effects belong in the 3D world, not under the shooter. On the host, remote players are
## ServerWorld entities and ServerWorld is a plain Node, so fall back to the current scene.
func _effects_parent() -> Node3D:
	var parent = entity.get_parent()
	if parent is Node3D:
		return parent
	var scene = entity.get_tree().current_scene if entity.is_inside_tree() else null
	return scene if scene is Node3D else entity

## Equip ranged weapon instance
func equip_ranged_weapon(weapon: RangedWeapon) -> void:
	equipped_ranged_weapon = weapon
	# Always emit weapon_changed signal when equipping ranged weapon
	weapon_changed.emit(weapon)
	print("[CombatComponent] Equipped ranged weapon: %s" % (weapon.item_name if weapon else "none"))

## Start reload process
func start_reload() -> void:
	if is_reloading or not equipped_ranged_weapon:
		return

	# Get inventory component for reserve ammo
	var inventory = entity.get_component("InventoryComponent") if entity else null
	var reserve_ammo = 999  # Default if no inventory

	if inventory:
		reserve_ammo = inventory.get_ammo_count(equipped_ranged_weapon.ammo_type)

	var ammo_to_reload = equipped_ranged_weapon.start_reload(reserve_ammo)
	if ammo_to_reload > 0:
		is_reloading = true
		reload_timer = equipped_ranged_weapon.reload_time
		reload_started.emit()

		# Consume ammo from inventory
		if inventory:
			inventory.consume_ammo(equipped_ranged_weapon.ammo_type, ammo_to_reload)

		print("[CombatComponent] Reloading... (%d rounds)" % ammo_to_reload)

## Complete reload after timer
func _complete_reload() -> void:
	is_reloading = false
	if equipped_ranged_weapon:
		# Ammo was already deducted, now add to magazine
		equipped_ranged_weapon.is_reloading = false
	reload_finished.emit()
	print("[CombatComponent] Reload complete")

func equip_weapon(weapon: WeaponData):
	current_weapon = weapon
	weapon_changed.emit(weapon)

func unequip_weapon():
	current_weapon = null
	weapon_changed.emit(null)

func get_weapon() -> WeaponData:
	return current_weapon

func set_base_damage(damage: float):
	base_damage = damage

func set_attack_range(range_value: float):
	attack_range = range_value

func set_ranged_damage_multiplier(value: float):
	ranged_damage_multiplier = max(0.0, value)
