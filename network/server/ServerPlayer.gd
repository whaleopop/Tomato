## Server-side player representation
extends Node
class_name ServerPlayer

var player_id: int = -1
var player_entity: Player = null
var last_input_time: float = 0.0
var character_name: String = ""  # Character class name for syncing

# Lag compensation: buffer of recent inputs with timestamps
var input_buffer: Array = []
const MAX_INPUT_BUFFER_SIZE: int = 60  # ~2 seconds at 30 inputs/sec
var last_processed_sequence: int = -1

func _ready():
	pass

## Connect to player entity signals for network broadcast
func connect_to_entity_signals():
	if not player_entity:
		return

	var combat = player_entity.get_component("CombatComponent")
	if combat:
		# Connect shot_fired to broadcast to other clients
		if not combat.shot_fired.is_connected(_on_shot_fired):
			combat.shot_fired.connect(_on_shot_fired)
	var abilities = player_entity.get_component("AbilityComponent")
	if abilities and not abilities.ability_cast.is_connected(_on_ability_cast):
		abilities.ability_cast.connect(_on_ability_cast)

## Shooting / casting gives you away for a moment (ServerVisibility, even from a bush)
func _mark_revealed():
	if is_instance_valid(player_entity):
		player_entity.set_meta("last_reveal_time", Time.get_ticks_msec() / 1000.0)

func _on_ability_cast(ability_index: int, target_position: Vector3):
	_mark_revealed()
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and is_instance_valid(player_entity):
		network_manager.broadcast_ability_cast(player_id, ability_index, target_position)

func _on_shot_fired(from_pos: Vector3, to_pos: Vector3, hit: bool):
	_mark_revealed()
	var status = player_entity.get_component("StatusComponent") if player_entity else null
	if status:
		status.clear("stealth")  # a shot gives a stealthed hero away
	# Get weapon type
	var weapon_type = 0  # PISTOL default
	var combat = player_entity.get_component("CombatComponent") if player_entity else null
	if combat and combat.equipped_ranged_weapon:
		weapon_type = combat.equipped_ranged_weapon.weapon_type

	# Broadcast to all clients via GameServer
	var game_server = get_parent() as GameServer
	if game_server:
		game_server.broadcast_shot_effect(player_id, from_pos, to_pos, weapon_type, hit)

func process_input(input_data: Dictionary):
	if not is_instance_valid(player_entity):
		return
	# The eliminated don't act: they are invisible and can't be shot back
	var health = player_entity.get_component("HealthComponent")
	if health and health.is_dead:
		return

	# Check sequence number to avoid processing old/duplicate inputs
	if input_data.has("sequence"):
		var seq = input_data["sequence"]
		if seq <= last_processed_sequence:
			# Old or duplicate input, ignore
			return
		last_processed_sequence = seq

	# Store input in buffer for lag compensation
	input_buffer.append({
		"data": input_data,
		"server_time": Time.get_ticks_msec(),
		"client_time": input_data.get("timestamp", 0)
	})

	# Trim buffer if too large
	while input_buffer.size() > MAX_INPUT_BUFFER_SIZE:
		input_buffer.pop_front()

	# Process movement input
	var movement = player_entity.get_component("MovementComponent")
	if movement:
		if input_data.has("move_direction"):
			var move_direction = Vector3(
				input_data.move_direction.x,
				0.0,
				input_data.move_direction.y
			)
			movement.set_move_direction(move_direction)
		else:
			movement.set_move_direction(Vector3.ZERO)

		# Process jump input
		if input_data.has("jump") and input_data.jump:
			movement.jump()

		# Process sprint input
		if input_data.has("sprint"):
			movement.set_sprint(input_data.sprint)

	# Facing direction (the client aims with the mouse)
	if input_data.has("rotation_y"):
		player_entity.rotation.y = float(input_data.rotation_y)

	# Keep the server entity's weapon state in step with the client
	if input_data.has("weapon_slot"):
		var inventory = player_entity.get_component("InventoryComponent")
		if inventory:
			inventory.switch_weapon_slot(int(input_data.weapon_slot))

	# Inventory menu actions of remote players
	var inventory_comp = player_entity.get_component("InventoryComponent")
	if inventory_comp:
		if input_data.has("use_item"):
			inventory_comp.use_item(int(input_data.use_item))
		if input_data.has("drop_item"):
			inventory_comp.remove_item(int(input_data.drop_item))

	if input_data.get("reload", false):
		var combat_comp = player_entity.get_component("CombatComponent")
		if combat_comp:
			combat_comp.start_reload()

	# Process attack input
	if input_data.has("attack") and input_data.attack:
		var combat = player_entity.get_component("CombatComponent")
		if combat:
			var target_pos = Vector3.ZERO
			if input_data.has("target_position"):
				target_pos = Vector3(
					input_data.target_position.x,
					input_data.target_position.y,
					input_data.target_position.z
				)

			# NEW: If client hit an entity, apply damage directly (server validates distance)
			if input_data.has("hit_entity_id"):
				var hit_entity_id = input_data.hit_entity_id
				_process_client_hit(player_entity, hit_entity_id, combat)
			else:
				# No hit reported by client, still call attack for effects and potential server-side hits
				combat.attack(target_pos)

	# Process ability input
	if input_data.has("ability_index"):
		var ability_component = player_entity.get_component("AbilityComponent")
		if ability_component:
			var target_pos = Vector3.ZERO
			if input_data.has("target_position"):
				target_pos = Vector3(
					input_data.target_position.x,
					input_data.target_position.y,
					input_data.target_position.z
				)
			ability_component.activate_ability(input_data.ability_index, target_pos)
	
	last_input_time = Time.get_ticks_msec() / 1000.0

func get_sync_data() -> Dictionary:
	if not is_instance_valid(player_entity) or not player_entity.is_inside_tree():
		return {}

	var data = {
		"player_id": player_id,
		"position": player_entity.global_position,
		"rotation": player_entity.global_rotation,
		"character_name": character_name,
	}

	# Add component data
	var health = player_entity.get_component("HealthComponent")
	if health:
		data["health"] = health.current_health
		data["max_health"] = health.max_health
		data["shield"] = health.shield

	var movement = player_entity.get_component("MovementComponent")
	if movement:
		data["velocity"] = movement.velocity
		data["is_moving"] = movement.is_moving

	# Add combat data for weapon sync
	var combat = player_entity.get_component("CombatComponent")
	if combat:
		data["is_attacking"] = combat.is_attacking
		data["is_reloading"] = combat.is_reloading
		if combat.equipped_ranged_weapon:
			data["weapon_type"] = combat.equipped_ranged_weapon.weapon_type
			data["current_ammo"] = combat.equipped_ranged_weapon.current_ammo
			data["magazine_size"] = combat.equipped_ranged_weapon.magazine_size

	# Stun, blind, stealth, knockback (StatusComponent): the victim's client acts on them
	var status = player_entity.get_component("StatusComponent")
	if status:
		var fx = status.to_sync()
		if not fx.is_empty():
			data["fx"] = fx

	return data

## Process client-reported hit with server-side validation
func _process_client_hit(attacker: Entity, target_entity_id: int, combat: CombatComponent):
	# Find target entity
	var target = _find_player_entity_by_id(target_entity_id)
	if not target:
		print("[ServerPlayer] WARNING: Target entity %d not found" % target_entity_id)
		return
	if target == attacker:
		return  # clicked on yourself
	# Same rules as a server-side shot: fire rate, reload, magazine
	if not combat.can_shoot():
		return
	var target_point = target.global_position + Vector3(0, 0.9, 0)
	# Only a single bullet is resolved by the client; pellets, fire and grenades by the server
	if combat.equipped_ranged_weapon and combat.equipped_ranged_weapon.fire_mode != "single":
		combat.attack(target_point)
		return
	# A wall between shooter and target stops the bullet: shoot it for real so it hits the wall
	if CoverSpawner.line_blocked(attacker.get_world_3d(), attacker.global_position + Vector3(0, 1.0, 0), target_point):
		combat.attack(target_point)
		return

	# Validate distance (anti-cheat: ensure target is in range)
	var distance = attacker.global_position.distance_to(target.global_position)
	var max_range = 50.0
	if combat.equipped_ranged_weapon:
		max_range = combat.equipped_ranged_weapon.range

	if distance > max_range + 5.0:  # +5.0 tolerance for latency
		print("[ServerPlayer] REJECTED: Target too far (possible cheat or latency)")
		return

	# Apply damage (server-authoritative)
	var damage = combat.base_damage
	if combat.equipped_ranged_weapon:
		damage = combat.equipped_ranged_weapon.damage * combat.get_damage_multiplier()

	var health_comp = target.get_component("HealthComponent")
	if health_comp:
		var actual_damage = health_comp.take_damage(damage, attacker)
		combat.target_hit.emit(target, actual_damage)
		if actual_damage > 0:
			combat.apply_on_hit(target)  # the Jam Blaster slows

		# Nobody else saw this shot (the client resolved it), so replicate the tracer
		_mark_revealed()
		var game_server = get_parent() as GameServer
		if game_server:
			var weapon_type = combat.equipped_ranged_weapon.weapon_type if combat.equipped_ranged_weapon else 0
			var muzzle = attacker.global_position + Vector3(0, 1.0, 0)
			game_server.broadcast_shot_effect(player_id, muzzle, target.global_position + Vector3(0, 0.8, 0), weapon_type, true, true)

		# Consume ammo (checked by can_shoot above); the last round starts the reload
		if combat.equipped_ranged_weapon:
			combat.equipped_ranged_weapon.consume_ammo()
			if combat.equipped_ranged_weapon.current_ammo <= 0:
				combat.start_reload()

		# Trigger cooldown
		combat.attack_cooldown = combat.equipped_ranged_weapon.fire_rate if combat.equipped_ranged_weapon else 0.5
	else:
		print("[ServerPlayer] WARNING: Target has no HealthComponent")

## Find player entity by entity_id
func _find_player_entity_by_id(entity_id: int) -> Entity:
	# Search in all players
	for pid in get_parent().players.keys():  # get_parent() should be GameServer
		var srv_player = get_parent().players[pid]
		if srv_player.player_entity and "entity_id" in srv_player.player_entity:
			if srv_player.player_entity.entity_id == entity_id:
				return srv_player.player_entity
	return null

