## Carrot character data (model generated from art/concepts/carrot.png)
extends CharacterData
class_name CarrotCharacter

func _init():
	character_name = "Carrot"
	description = "A swift orange fighter with sharp precision"
	base_health = 160.0
	base_speed = 7.5
	model_path = "res://models/characters/Carrot.glb"
	color = Color(1.0, 0.45, 0.12)
	model_scale = 1.0  # Auto-normalized to the standard height
	model_origin_at_feet = true
	
	# Active ability: Carrot Strike - fast dash attack
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Carrot Strike"
	active_ability_data.description = "Quick dash forward, hitting everyone in the path for 25 damage"
	active_ability_data.cooldown = 6.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/CarrotStrike.gd"
	active_ability = active_ability_data
	
	# Passive ability: Swift Movement - increased movement speed
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Swift Movement"
	passive_ability_data.description = "10% increased movement speed"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/SpeedBoost.gd"
	passive_ability = passive_ability_data
