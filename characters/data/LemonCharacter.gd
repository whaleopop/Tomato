## Lemon character data (model generated from art/concepts/lemon.png)
extends CharacterData
class_name LemonCharacter

func _init():
	character_name = "Lemon"
	description = "Small, fast and very sour. Leaves a sting"
	base_health = 80.0
	base_speed = 7.5
	model_path = "res://models/characters/Lemon.glb"
	color = Color(1.0, 0.82, 0.15)
	model_scale = 1.0  # Auto-normalized to the standard height
	model_origin_at_feet = true

	# Active ability: Sour Squirt
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Sour Squirt"
	active_ability_data.description = "Sprays acidic lemon juice that burns enemies"
	active_ability_data.cooldown = 7.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/TomatoSplash.gd"
	active_ability = active_ability_data

	# Passive ability: Zest
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Zest"
	passive_ability_data.description = "Moves faster than most fruit"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/SpeedBoost.gd"
	passive_ability = passive_ability_data
