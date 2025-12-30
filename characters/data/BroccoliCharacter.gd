## Broccoli character data
extends CharacterData
class_name BroccoliCharacter

func _init():
	character_name = "Broccoli"
	description = "A defensive support with healing capabilities"
	base_health = 100.0
	base_speed = 5.0
	model_path = "res://models/Broccoli.glb"
	
	# Active ability: Healing Sprout - heals self and nearby allies
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Healing Sprout"
	active_ability_data.description = "Heals self and nearby allies over time"
	active_ability_data.cooldown = 12.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/HealingSprout.gd"
	active_ability = active_ability_data
	
	# Passive ability: Regenerative - increased health regeneration
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Regenerative"
	passive_ability_data.description = "Passive health regeneration"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/HealthRegeneration.gd"
	passive_ability = passive_ability_data

