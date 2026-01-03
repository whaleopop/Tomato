## Carrot character data
extends CharacterData
class_name CarrotCharacter

func _init():
	character_name = "Carrot"
	description = "A swift orange fighter with sharp precision"
	base_health = 80.0
	base_speed = 7.5
	model_path = "res://models/Carrot.glb"
	color = Color(1.0, 0.6, 0.2)  # Orange
	model_scale = 0.7
	model_offset = Vector3(0, 0.1, 0)
	
	# Active ability: Carrot Strike - fast dash attack
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Carrot Strike"
	active_ability_data.description = "Quick dash forward dealing damage to enemies in path"
	active_ability_data.cooldown = 6.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/Dash.gd"
	active_ability = active_ability_data
	
	# Passive ability: Swift Movement - increased movement speed
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Swift Movement"
	passive_ability_data.description = "10% increased movement speed"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/SpeedBoost.gd"
	passive_ability = passive_ability_data

