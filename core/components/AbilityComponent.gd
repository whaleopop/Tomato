## Manages active and passive abilities
extends Component
class_name AbilityComponent

signal ability_activated(ability: ActiveAbility)
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
	
	# Check cooldown
	if ability_cooldowns.has(ability) and ability_cooldowns[ability] > 0.0:
		return false
	
	# Activate ability (async)
	_activate_ability_async(ability, target_position)
	
	# Set cooldown immediately
	ability_cooldowns[ability] = ability.cooldown
	ability_activated.emit(ability)
	
	return true

func _activate_ability_async(ability: ActiveAbility, target_position: Vector3):
	var success = await ability.activate(entity, target_position)
	if not success:
		# Remove cooldown if activation failed
		ability_cooldowns.erase(ability)

func get_ability_cooldown(ability: ActiveAbility) -> float:
	return ability_cooldowns.get(ability, 0.0)

func get_ability_cooldown_percent(ability: ActiveAbility) -> float:
	if not ability_cooldowns.has(ability):
		return 0.0
	return ability_cooldowns[ability] / ability.cooldown

