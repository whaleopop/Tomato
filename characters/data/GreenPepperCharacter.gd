## Green Pepper character data
extends CharacterData
class_name GreenPepperCharacter

func _init():
	character_name = "Green Pepper"
	description = "An agile fighter with spicy attacks"
	base_health = 75.0
	base_speed = 8.0
	model_path = "res://models/Green Pepper.glb"
	color = Color(0.3, 0.8, 0.3)  # Light green
	model_scale = 0.7
	model_offset = Vector3(0, 0, 0)
	
	# Active ability: Spicy Dash - fast movement with damage trail
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Spicy Dash"
	active_ability_data.description = "Quick dash leaving a trail of fire"
	active_ability_data.cooldown = 5.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/Dash.gd"
	active_ability = active_ability_data
	
	# Passive ability: Agile - increased dodge chance
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Agile"
	passive_ability_data.description = "10% chance to dodge attacks"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/DodgeChance.gd"
	passive_ability = passive_ability_data

