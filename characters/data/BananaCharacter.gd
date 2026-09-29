## Banana character data (model generated from art/concepts/banana.png)
extends CharacterData
class_name BananaCharacter

func _init():
	character_name = "Banana"
	description = "Quick, slippery and always ready to throw a peel under your feet"
	base_health = 170.0
	base_speed = 7.0
	model_path = "res://models/characters/Banana.glb"
	color = Color(1.0, 0.88, 0.2)
	model_scale = 1.0  # Auto-normalized to the standard height
	model_origin_at_feet = true

	# Active ability: Peel Trap
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Peel Trap"
	active_ability_data.description = "Tosses a banana peel: the first enemy to step on it slips and is stunned for a second"
	active_ability_data.cooldown = 8.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/PeelTrap.gd"
	active_ability = active_ability_data

	# Passive ability: Slippery
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Slippery"
	passive_ability_data.description = "15% chance to dodge attacks"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/DodgeChance.gd"
	passive_ability = passive_ability_data
