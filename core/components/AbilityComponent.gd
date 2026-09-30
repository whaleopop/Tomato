## Manages active and passive abilities
extends Component
class_name AbilityComponent

signal ability_activated(ability: ActiveAbility)
signal ability_cast(ability_index: int, target_position: Vector3)  # the server replicates it
signal ability_cooldown_finished(ability: ActiveAbility)
signal passive_ability_applied(ability: PassiveAbility)

var active_abilities: Array[ActiveAbility] = []
var passive_abilities: Array[PassiveAbility] = []
var ability_cooldowns: Dictionary = {}

func _init(p_entity = null):  # p_entity: Entity
	entity = p_entity

func update(delta: float):
	if not enabled:
		return

	# Update cooldowns
	for ability in active_abilities:
		if ability_cooldowns.has(ability):
			var cooldown = ability_cooldowns[ability]
			if cooldown > 0.0:
				cooldown -= delta
				ability_cooldowns[ability] = cooldown

				if cooldown <= 0.0:
					ability_cooldown_finished.emit(ability)
					ability_cooldowns.erase(ability)

	# Update passive abilities
	for passive in passive_abilities:
		if passive.enabled:
			passive.update(delta, entity)

func add_active_ability(ability: ActiveAbility):
	if ability == null:
		return

	if not active_abilities.has(ability):
		active_abilities.append(ability)
		ability.initialize(entity)

func remove_active_ability(ability: ActiveAbility):
	var index = active_abilities.find(ability)
	if index >= 0:
		active_abilities.remove_at(index)
		ability_cooldowns.erase(ability)
		ability.cleanup()

func add_passive_ability(ability: PassiveAbility):
	if ability == null:
		return

	if not passive_abilities.has(ability):
		passive_abilities.append(ability)
		ability.apply(entity)
		passive_ability_applied.emit(ability)

func remove_passive_ability(ability: PassiveAbility):
	var index = passive_abilities.find(ability)
	if index >= 0:
		passive_abilities.remove_at(index)
		ability.remove(entity)

func activate_ability(ability_index: int, target_position: Vector3 = Vector3.ZERO) -> bool:
	if ability_index < 0 or ability_index >= active_abilities.size():
		return false

	var ability = active_abilities[ability_index]
	var inventory = entity.get_component("InventoryComponent") if entity and entity.has_method("get_component") else null
	if inventory:
		inventory.cancel_use()  # casting stops a heal / shield in progress

	# Check cooldown
	if ability_cooldowns.has(ability) and ability_cooldowns[ability] > 0.0:
		return false
	var status = entity.get_component("StatusComponent") if entity and entity.has_method("get_component") else null
	if status and status.is_stunned():
		return false

	# Set the cooldown first: a failure that returns at once clears it again (the old order
	# cleared it and then set it, so failed casts still cost the full cooldown)
	ability_cooldowns[ability] = effective_cooldown(ability)
	ability_activated.emit(ability)
	ability_cast.emit(ability_index, target_position)
	_activate_ability_async(ability, target_position)
	return true

## Show another player's cast on our copy of them (visual replay: the server did the real one)
func play_remote_cast(ability_index: int, target_position: Vector3):
	if ability_index < 0 or ability_index >= active_abilities.size():
		return
	var ability = active_abilities[ability_index]
	ability_cooldowns[ability] = effective_cooldown(ability)  # their HUD-less cooldown, just for consistency
	ability_activated.emit(ability)
	ability.replay = true
	await ability.activate(entity, target_position)
	ability.replay = false

func _activate_ability_async(ability: ActiveAbility, target_position: Vector3):
	var success = await ability.activate(entity, target_position)
	if not success:
		# Remove cooldown if activation failed
		ability_cooldowns.erase(ability)

## Mushroom grove (BiomeRules): the running cooldowns lose `seconds` more
func advance_cooldowns(seconds: float) -> void:
	for ability in ability_cooldowns.keys():
		var left = ability_cooldowns[ability] - seconds
		if left <= 0.01:
			ability_cooldowns.erase(ability)
			ability_cooldown_finished.emit(ability)
		else:
			ability_cooldowns[ability] = left

## Ability crystal pickup: cut every running cooldown by `fraction` (1.0 = ready right away)
func boost_cooldowns(fraction: float) -> void:
	for ability in ability_cooldowns.keys():
		var left = ability_cooldowns[ability] * (1.0 - clamp(fraction, 0.0, 1.0))
		if left <= 0.01:
			ability_cooldowns.erase(ability)
			ability_cooldown_finished.emit(ability)
		else:
			ability_cooldowns[ability] = left

func get_ability_cooldown(ability: ActiveAbility) -> float:
	return ability_cooldowns.get(ability, 0.0)

func get_ability_cooldown_percent(ability: ActiveAbility) -> float:
	if not ability_cooldowns.has(ability):
		return 0.0
	return ability_cooldowns[ability] / max(effective_cooldown(ability), 0.01)

## The ability's cooldown for this hero (the Zest passive shortens it: meta "cooldown_factor")
func effective_cooldown(ability: ActiveAbility) -> float:
	var factor = float(entity.get_meta("cooldown_factor", 1.0)) if entity else 1.0
	return ability.cooldown * factor

