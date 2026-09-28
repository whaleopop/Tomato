## Broccoli character data (model generated from art/concepts/broccoli.png)
extends CharacterData
class_name BroccoliCharacter

func _init():
	character_name = "Broccoli"
	description = "A defensive support with healing capabilities"
	base_health = 100.0
	base_speed = 5.0
	model_path = "res://models/characters/Broccoli.glb"
	color = Color(0.35, 0.68, 0.22)
	model_scale = 1.0  # Auto-normalized to the standard height
	model_origin_at_feet = true
	
	# Active ability: Healing Sprout - heals self over time
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Healing Sprout"
	active_ability_data.description = "Heals 30 HP over 3 seconds"
	active_ability_data.cooldown = 12.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/HealingSprout.gd"
	active_ability = active_ability_data
	
	# Passive ability: Photosynthesis
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Photosynthesis"
	passive_ability_data.description = "Standing still for a second heals 5 HP per second"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/Photosynthesis.gd"
	passive_ability = passive_ability_data
