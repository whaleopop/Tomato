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
var _reload_amount: int = 0                  # rounds taken from the reserve for the running reload
var _reload_weapon: RangedWeapon = null      # the gun being reloaded

# Muzzle offset from entity position: right, up, forward (where WeaponVisualComponent holds the gun)
var muzzle_offset: Vector3 = Vector3(0.28, 0.66, 0.6)

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

## The gun's reach and the time between its shots for this hero (Weed Swarm perks: metas
## "range_factor" / "fire_rate_factor", SwarmPerks)
func reach() -> float:
	if not equipped_ranged_weapon:
		return attack_range
	return equipped_ranged_weapon.range * (float(entity.get_meta("range_factor", 1.0)) if entity else 1.0)

func shot_interval() -> float:
	if not equipped_ranged_weapon:
		return 0.5
	return equipped_ranged_weapon.fire_rate * (float(entity.get_meta("fire_rate_factor", 1.0)) if entity else 1.0)

func can_attack() -> bool:
	return enabled and attack_cooldown <= 0.0 and not is_attacking and not is_reloading and not _stunned()

func _stunned() -> bool:
	var status = entity.get_component("StatusComponent") if entity and entity.has_method("get_component") else null
	return status != null and status.is_stunned()

## Everything that scales weapon damage: pickups and perks (ranged_damage_multiplier) and the
## Hot Temper passive (meta "hot_temper": the factor while below half health)
func get_damage_multiplier() -> float:
	var m = ranged_damage_multiplier
	if entity and entity.has_meta("hot_temper"):
		var health = entity.get_component("HealthComponent")
		if health and health.max_health > 0.0 and health.current_health < health.max_health * 0.5:
			m *= float(entity.get_meta("hot_temper"))
	return m

func can_shoot() -> bool:
	if not can_attack():
		return false
	if equipped_ranged_weapon:
		return equipped_ranged_weapon.can_shoot()
	return current_weapon != null and current_weapon.weapon_type == "ranged"

## Perform attack - uses hitscan for ranged weapons
## When this hero last pulled the trigger: damage soon after counts for the gun's mastery
## (ServerPlayer.credited_weapon), not for an ability
var last_shot_msec: int = -100000
const WEAPON_CREDIT_MSEC: int = 3500  # grenades fly, fire burns for a while

## The gun type the damage dealt right now is credited to, -1 = not a gun (an ability, thorns...)
func credited_weapon() -> int:
	if equipped_ranged_weapon and Time.get_ticks_msec() - last_shot_msec < WEAPON_CREDIT_MSEC:
		return int(equipped_ranged_weapon.weapon_type)
	return -1

func attack(target_position: Vector3, target_entity = null) -> bool:  # target_entity: Entity
	if not can_attack():
		return false
	var inventory = entity.get_component("InventoryComponent") if entity and entity.has_method("get_component") else null
	if inventory:
		inventory.cancel_use()  # shooting stops a heal / shield in progress
	last_shot_msec = Time.get_ticks_msec()

	is_attacking = true
	attack_started.emit()

	var damage = base_damage

	# NEW: Check for equipped ranged weapon first (new weapon system)
	if equipped_ranged_weapon:
		damage = equipped_ranged_weapon.damage * get_damage_multiplier()
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

	# How this gun fires (RangedWeapon.fire_mode) and how its tracer looks
	var mode = "single"
	var style = "pistol"
	if equipped_ranged_weapon:
		mode = equipped_ranged_weapon.fire_mode
		style = equipped_ranged_weapon.effect_style
		damage = equipped_ranged_weapon.damage * get_damage_multiplier()
		attack_range = reach()
		attack_cooldown = shot_interval()
	elif current_weapon:
		var legacy = current_weapon.weapon_name.to_lower()
		if legacy.contains("shotgun"):
			mode = "spread"
		elif legacy.contains("sniper"):
			mode = "pierce"
			style = "sniper"
		elif legacy.contains("flame"):
			mode = "flame"
		elif legacy.contains("rifle"):
			style = "rifle"

	var hit_result: Dictionary
	var hit_results: Array[Dictionary] = []
	var end_pos = target_position

	# CRITICAL: Apply damage ONLY on server to prevent double-damage bug
	var is_server = entity.get_tree().get_multiplayer().is_server()

	match mode:
		"spread":
			var pellet_count = 8
			var spread = 25.0
			if equipped_ranged_weapon:
				pellet_count = equipped_ranged_weapon.pellet_count
				spread = equipped_ranged_weapon.spread_angle

			hit_results = HitscanSystem.shoot_spread(
				world_3d, muzzle_pos, direction,
				pellet_count, min(spread * MapEvents.spread_factor, 60.0), attack_range, damage, entity
			)
			for result in hit_results:
				if result.get("hit", false) and is_server:
					var actual_dmg = HitscanSystem.apply_hit_damage(result, entity)
					if actual_dmg > 0:
						target_hit.emit(result.get("collider"), actual_dmg)
						apply_on_hit(result.get("collider"))
			_create_shot_effects_shotgun(muzzle_pos, hit_results)
			shot_fired.emit(muzzle_pos, target_position, hit_results.size() > 0)

		"pierce":
			hit_results = HitscanSystem.shoot_penetrating(
				world_3d, muzzle_pos, _apply_accuracy(direction, 1.0),  # dead straight unless the ground shakes
				attack_range, damage, 2, 0.6, entity
			)
			for result in hit_results:
				if result.get("hit", false) and is_server:
					var actual_dmg = HitscanSystem.apply_hit_damage(result, entity)
					if actual_dmg > 0:
						target_hit.emit(result.get("collider"), actual_dmg)
			if hit_results.size() > 0:
				end_pos = hit_results[-1].get("position", target_position)
				_create_shot_effects(muzzle_pos, hit_results[0], style)
			shot_fired.emit(muzzle_pos, end_pos, hit_results.size() > 0)

		"flame":
			# Flamethrower - cone of fire with burn effect
			_perform_flamethrower_attack(muzzle_pos, direction, damage)
			shot_fired.emit(muzzle_pos, muzzle_pos + direction * attack_range, true)

		"lob":
			# Grenade launcher: an arc onto the aimed spot, the blast there a moment later
			var land = _lob_target(muzzle_pos, target_position)
			var radius = equipped_ranged_weapon.blast_radius if equipped_ranged_weapon else 2.5
			GrenadeFX.lob(_effects_parent(), muzzle_pos, land, radius)
			if is_server:
				_blast_later(land, radius, damage, GrenadeFX.flight_time(muzzle_pos, land))
			end_pos = land
			shot_fired.emit(muzzle_pos, land, false)

		_:  # "single": one bullet, spread by the gun's accuracy (pistol, rifle, SMG, ...)
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
					apply_on_hit(hit_result.get("collider"))
			end_pos = hit_result.get("position", muzzle_pos + direction * attack_range)
			_create_shot_effects(muzzle_pos, hit_result, style)
			shot_fired.emit(muzzle_pos, end_pos, hit_result.get("hit", false))

	# The bang (every peer that runs this shot: the shooter's client, the host for its players;
	# the others hear it from NetworkManager._create_remote_shot_effects)
	if equipped_ranged_weapon:
		Sfx.shot(int(equipped_ranged_weapon.weapon_type), muzzle_pos)
	if entity and entity.get("is_local_player"):
		var landed = hit_results.any(func(r): return r.get("hit", false) and r.get("collider") is Entity)
		if hit_result and hit_result.get("hit", false) and hit_result.get("collider") is Entity:
			landed = true
		if landed:
			Sfx.own("hit")

	# Add bullet trail to visibility system
	_add_visibility_trail(muzzle_pos, end_pos)

	# The last round is out: reload on its own if there is anything to reload with
	if equipped_ranged_weapon and equipped_ranged_weapon.current_ammo <= 0:
		start_reload()

	# Camera shake for feedback
	if ScreenEffects.instance:
		var shake_intensity = 0.1
		if mode == "pierce" or style == "sniper":
			shake_intensity = 0.3
		elif mode == "spread" or mode == "lob":
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
			var weapon_type_str = "shotgun" if mode == "spread" else style

			# Only send RPC if we're the authority (local player or server)
			if entity.has_method("is_local_player") and entity.is_local_player:
				var combat_sync = tree.root.get_node_or_null("/root/NetworkCombatSync")
				if combat_sync:
					combat_sync.sync_shot_fired.rpc(entity.entity_id, muzzle_pos, end_pos, weapon_type_str, hit_result.get("hit", false), hit_target_id)

	return true

## After a hit (server): what the gun does besides damage - the Jam Blaster's slow
func apply_on_hit(target) -> void:
	if not equipped_ranged_weapon or equipped_ranged_weapon.slow_on_hit <= 0.0:
		return
	if target and is_instance_valid(target) and target.has_method("get_component"):
		var status = target.get_component("StatusComponent")
		if status:
			status.apply("slow", equipped_ranged_weapon.slow_time, equipped_ranged_weapon.slow_on_hit)

## Where a lobbed grenade comes down: the aimed spot, no further than the gun's range, on the ground
func _lob_target(from: Vector3, target: Vector3) -> Vector3:
	var flat = target - entity.global_position
	flat.y = 0.0
	if flat.length() > attack_range:
		flat = flat.normalized() * attack_range
	var spot = entity.global_position + flat
	var space = entity.get_world_3d().direct_space_state
	var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 4.0, spot + Vector3.DOWN * 6.0, 1))
	if hit:
		spot.y = hit.position.y
	return spot

## Server: the grenade lands after `delay` - everyone in `radius` gets hurt, less at the edge
func _blast_later(pos: Vector3, radius: float, damage: float, delay: float) -> void:
	var shooter = entity
	await shooter.get_tree().create_timer(delay).timeout
	if not is_instance_valid(shooter) or not shooter.is_inside_tree():
		return
	for other in shooter.get_tree().get_nodes_in_group("entities"):
		if other == shooter or not other is Node3D or not other.has_method("get_component"):
			continue
		var off: Vector3 = other.global_position - pos
		if abs(off.y) > 2.0:
			continue
		off.y = 0.0
		var d = off.length()
		if d > radius:
			continue
		var health = other.get_component("HealthComponent")
		if health:
			var dealt = health.take_damage(damage * (1.0 - 0.5 * d / radius), shooter)
			if dealt > 0:
				target_hit.emit(other, dealt)
		var status = other.get_component("StatusComponent")
		if status and d > 0.05:
			status.push(off.normalized() * 6.0, 0.2)

## Apply accuracy spread to direction
func _apply_accuracy(direction: Vector3, accuracy: float) -> Vector3:
	var spread = (1.0 - accuracy) * 0.15
	# Earthquake (MapEvents): everybody's aim shakes, even a sniper's
	if MapEvents.spread_factor > 1.0:
		spread = max(spread, 0.012) * MapEvents.spread_factor
	if spread <= 0.0:
		return direction
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
	particles.amount = 26
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.explosiveness = 0.8

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = direction
	mat.spread = 14.0
	mat.initial_velocity_min = 14.0
	mat.initial_velocity_max = 22.0
	mat.damping_min = 12.0
	mat.damping_max = 18.0
	mat.gravity = Vector3(0, 3, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	var grow = Curve.new()  # tongues of fire widen as they fly
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(0.5, 1.0))
	grow.add_point(Vector2(1.0, 1.4))
	var grow_tex = CurveTexture.new()
	grow_tex.curve = grow
	mat.scale_curve = grow_tex

	var gradient = GradientTexture1D.new()
	var grad = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.9, 0.35, 1.0), Color(1.0, 0.5, 0.1, 0.9), Color(0.85, 0.2, 0.05, 0.55), Color(0.2, 0.1, 0.1, 0.0)])
	gradient.gradient = grad
	mat.color_ramp = gradient

	particles.process_material = mat
	# Soft billboards with the fire material (a bare SphereMesh drew plain white balls)
	var quad = QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	quad.material = FireTrail._get_flame_material()
	particles.draw_pass_1 = quad

	parent.add_child(particles)
	particles.global_position = muzzle_pos  # after add_child: outside the tree it is ignored

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

	# Heroes face +Z (PlayerInputHandler: rotation.y = atan2(x, z)); the right hand is at -X
	var forward = entity.transform.basis.z
	var right = -entity.transform.basis.x
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
	if weapon != equipped_ranged_weapon:
		cancel_reload()  # switching mid-reload used to leave the old gun "reloading" forever
	equipped_ranged_weapon = weapon
	# Always emit weapon_changed signal when equipping ranged weapon
	weapon_changed.emit(weapon)
	print("[CombatComponent] Equipped ranged weapon: %s" % (weapon.item_name if weapon else "none"))

## Start reload process
func start_reload() -> void:
	if is_reloading or not equipped_ranged_weapon:
		return

	# Get inventory component for reserve ammo (Weed Swarm: the reserve never runs out)
	var inventory = entity.get_component("InventoryComponent") if entity and not entity.has_meta("endless_ammo") else null
	var reserve_ammo = 999  # Default if no inventory

	if inventory:
		reserve_ammo = inventory.get_ammo_count(equipped_ranged_weapon.ammo_type)

	var ammo_to_reload = equipped_ranged_weapon.start_reload(reserve_ammo)
	if ammo_to_reload > 0:
		# The rounds leave the reserve now and go into the magazine when the reload is done
		if inventory:
			ammo_to_reload = inventory.consume_ammo(equipped_ranged_weapon.ammo_type, ammo_to_reload)
		if ammo_to_reload <= 0:
			equipped_ranged_weapon.is_reloading = false
			return
		is_reloading = true
		reload_timer = equipped_ranged_weapon.reload_time * float(entity.get_meta("reload_factor", 1.0))
		_reload_amount = ammo_to_reload
		_reload_weapon = equipped_ranged_weapon
		reload_started.emit()
		if entity.get("is_local_player"):
			Sfx.own("reload")
		print("[CombatComponent] Reloading... (%d rounds)" % ammo_to_reload)

## Complete reload after timer: the rounds taken from the reserve go into the magazine
## (they used to vanish: the reserve went down, the magazine stayed empty)
func _complete_reload() -> void:
	is_reloading = false
	if _reload_weapon:
		_reload_weapon.complete_reload(_reload_amount)
	_reload_amount = 0
	_reload_weapon = null
	reload_finished.emit()
	if entity and entity.get("is_local_player"):
		Sfx.own("reload_done")
	print("[CombatComponent] Reload complete")

## Stop a running reload (weapon switched, dropped...): the rounds go back into the reserve
func cancel_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	reload_timer = 0.0
	if _reload_weapon:
		_reload_weapon.is_reloading = false
		var inventory = entity.get_component("InventoryComponent") if entity and not entity.has_meta("endless_ammo") else null
		if inventory and _reload_amount > 0:
			inventory.add_item(AmmoItem.new(_reload_weapon.ammo_type, _reload_amount))
	_reload_amount = 0
	_reload_weapon = null
	reload_finished.emit()

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
