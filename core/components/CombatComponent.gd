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
		return false

	# Check and consume ammo
	if equipped_ranged_weapon:
		if not equipped_ranged_weapon.consume_ammo():
			# Out of ammo - start reload
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
	var weapon_type = "pistol"
	if current_weapon:
		if current_weapon.weapon_name.to_lower().contains("shotgun"):
			weapon_type = "shotgun"
		elif current_weapon.weapon_name.to_lower().contains("sniper"):
			weapon_type = "sniper"

	var hit_result: Dictionary
	var hit_results: Array[Dictionary] = []

	# Perform appropriate shot type
	match weapon_type:
		"shotgun":
			hit_results = HitscanSystem.shoot_spread(
				world_3d, muzzle_pos, direction,
				8, 15.0, 30.0, damage / 3.0, entity
			)
			# Apply damage from all pellets
			for result in hit_results:
				if result.get("hit", false):
					var actual_dmg = HitscanSystem.apply_hit_damage(result, entity)
					if actual_dmg > 0:
						target_hit.emit(result.get("collider"), actual_dmg)
			# Visual effects
			_create_shot_effects_shotgun(muzzle_pos, hit_results)
			shot_fired.emit(muzzle_pos, target_position, hit_results.size() > 0)

		"sniper":
			hit_results = HitscanSystem.shoot_penetrating(
				world_3d, muzzle_pos, direction,
				attack_range, damage, 2, 0.6, entity
			)
			# Apply damage to all penetrated targets
			for result in hit_results:
				if result.get("hit", false):
					var actual_dmg = HitscanSystem.apply_hit_damage(result, entity)
					if actual_dmg > 0:
						target_hit.emit(result.get("collider"), actual_dmg)
			# Visual effects for first hit
			if hit_results.size() > 0:
				_create_shot_effects(muzzle_pos, hit_results[0], weapon_type)
			shot_fired.emit(muzzle_pos, target_position, hit_results.size() > 0)

		_:  # Default pistol/rifle
			hit_result = HitscanSystem.shoot(
				world_3d, muzzle_pos, direction,
				attack_range, damage, entity
			)
			if hit_result.get("hit", false):
				var actual_dmg = HitscanSystem.apply_hit_damage(hit_result, entity)
				if actual_dmg > 0:
					target_hit.emit(hit_result.get("collider"), actual_dmg)
			# Visual effects
			_create_shot_effects(muzzle_pos, hit_result, weapon_type)
			shot_fired.emit(muzzle_pos, hit_result.get("position", target_position), hit_result.get("hit", false))

	# Camera shake for feedback
	if ScreenEffects.instance:
		ScreenEffects.shake(0.1, 8.0)

	return true

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

	var parent = entity.get_parent()
	if not parent:
		parent = entity

	var hit_pos = hit_result.get("position", muzzle_pos + (entity.global_position - muzzle_pos).normalized() * 50)
	var hit_normal = hit_result.get("normal", Vector3.UP)
	var collider = hit_result.get("collider")

	WeaponEffects.create_shot_effects(parent, muzzle_pos, hit_pos, hit_normal, collider, weapon_type)

## Create visual effects for shotgun spread
func _create_shot_effects_shotgun(muzzle_pos: Vector3, results: Array[Dictionary]) -> void:
	if not entity or not is_instance_valid(entity):
		return

	var parent = entity.get_parent()
	if not parent:
		parent = entity

	WeaponEffects.create_shotgun_effects(parent, muzzle_pos, results)

## Equip ranged weapon instance
func equip_ranged_weapon(weapon: RangedWeapon) -> void:
	equipped_ranged_weapon = weapon
	if weapon and weapon.weapon_data:
		equip_weapon(weapon.weapon_data)

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

