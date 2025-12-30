## Turnip character data
extends CharacterData
class_name TurnipCharacter

func _init():
	character_name = "Turnip"
	description = "A balanced warrior with versatile abilities"
	base_health = 95.0
	base_speed = 6.0
	model_path = "res://models/Turnip.glb"
	color = Color(0.9, 0.85, 0.8)  # Light cream/white
	
	# Active ability: Turnip Toss - throws self for area damage
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Turnip Toss"
	active_ability_data.description = "Leaps to target location dealing damage on impact"
	active_ability_data.cooldown = 9.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/TurnipToss.gd"
	active_ability = active_ability_data
	
	# Passive ability: Balanced - small bonuses to all stats
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Balanced"
	passive_ability_data.description = "5% bonus to all stats"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/BalancedStats.gd"
	passive_ability = passive_ability_data

