## Synchronizes combat actions across network
## Handles shooting, damage, and weapon effects for all players
extends Node

## Broadcast a shot fired event to all clients
@rpc("any_peer", "unreliable")
func sync_shot_fired(shooter_id: int, from: Vector3, to: Vector3, weapon_type: String, hit: bool, hit_target_id: int = -1):
	# Don't process on server - server already handled the shot locally
	if multiplayer.is_server():
		return

	print("[NetworkCombatSync] Received shot_fired from player %d, weapon: %s" % [shooter_id, weapon_type])

	# Find shooter entity to create visual effects
	var shooter = _find_player_by_id(shooter_id)
	if not shooter:
		print("[NetworkCombatSync] Shooter %d not found" % shooter_id)
		return

	var combat = shooter.get_component("CombatComponent")
	if not combat:
		return

	# Create visual effects based on weapon type
	var parent = shooter.get_parent()
	if not parent:
		parent = shooter.get_tree().current_scene

	var hit_result = {
		"hit": hit,
		"position": to,
		"normal": Vector3.UP,
		"collider": null
	}

	# Find hit target if specified
	if hit and hit_target_id > 0:
		var target = _find_player_by_id(hit_target_id)
		if target:
			hit_result["collider"] = target

	# Create effects based on weapon type
	match weapon_type:
		"pistol", "rifle":
			WeaponEffects.create_shot_effects(parent, from, to, Vector3.UP, hit_result.get("collider"), weapon_type)
		"shotgun":
			# For shotgun, create simplified effect (we don't sync all pellets)
			WeaponEffects.create_muzzle_flash(parent, from, (to - from).normalized())
			WeaponEffects.create_tracer(parent, from, to, Color(1, 0.6, 0.3), 0.08)
		"sniper":
			WeaponEffects.create_shot_effects(parent, from, to, Vector3.UP, hit_result.get("collider"), "sniper")

	# Play sound effects (if you have them)
	# AudioManager.play_gunshot(weapon_type, from)

## Broadcast weapon change to all clients
@rpc("any_peer", "call_local", "reliable")
func sync_weapon_changed(player_id: int, weapon_name: String, current_ammo: int, max_ammo: int):
	print("[NetworkCombatSync] Player %d changed weapon to %s (%d/%d)" % [player_id, weapon_name, current_ammo, max_ammo])

	var player = _find_player_by_id(player_id)
	if not player:
		return

	# Update weapon visual if exists
	var weapon_visual = player.get_node_or_null("WeaponVisual")
	if weapon_visual and weapon_visual.has_method("update_weapon"):
		weapon_visual.update_weapon(weapon_name)

## Broadcast reload action
@rpc("any_peer", "call_local", "reliable")
func sync_reload(player_id: int):
	print("[NetworkCombatSync] Player %d reloading" % player_id)

	var player = _find_player_by_id(player_id)
	if not player:
		return

	# Play reload animation/sound
	# AnimationManager.play_reload(player)

## Find player entity by ID
func _find_player_by_id(player_id: int):
	# Try to find in ClientWorld
	var client_world = get_tree().get_first_node_in_group("client_world")
	if client_world and client_world.has_method("get_player"):
		return client_world.players.get(player_id)

	# Fallback: search in scene tree
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if "entity_id" in player and player.entity_id == player_id:
			return player

	return null
