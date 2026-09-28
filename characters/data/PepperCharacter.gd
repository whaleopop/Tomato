## Pepper character data (model generated from art/concepts/pepper.png)
extends CharacterData
class_name PepperCharacter

func _init():
	character_name = "Pepper"
	description = "A hot-tempered bell pepper with spicy attacks"
	base_health = 75.0
	base_speed = 8.0
	model_path = "res://models/characters/Pepper.glb"
	color = Color(0.9, 0.18, 0.12)
	model_scale = 1.0  # Auto-normalized to the standard height
	model_origin_at_feet = true
	
	# Active ability: Spicy Dash - fast movement with damage trail
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Spicy Dash"
	active_ability_data.description = "Quick dash leaving a trail of fire that burns for 3 s (10 damage per second)"
	active_ability_data.cooldown = 5.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/SpicyDash.gd"
	active_ability = active_ability_data
	
	# Passive ability: Hot Temper
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Hot Temper"
	passive_ability_data.description = "Below half health, weapons deal 25% more damage"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/HotTemper.gd"
	passive_ability = passive_ability_data

