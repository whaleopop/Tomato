## Pumpkin character data
extends CharacterData
class_name PumpkinCharacter

func _init():
	character_name = "Pumpkin"
	description = "A massive tank with thick protective shell"
	base_health = 150.0
	base_speed = 4.0
	model_path = "res://models/Pumpkin.glb"
	
	# Active ability: Pumpkin Smash - area damage around self
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Pumpkin Smash"
	active_ability_data.description = "Smashes the ground dealing damage to nearby enemies"
	active_ability_data.cooldown = 10.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/PumpkinSmash.gd"
	active_ability = active_ability_data
	
	# Passive ability: Thick Shell - damage resistance
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Thick Shell"
	passive_ability_data.description = "15% damage resistance"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/DamageResistance.gd"
	passive_ability = passive_ability_data

