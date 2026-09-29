## Corn character data (model generated from art/concepts/corn.png)
extends CharacterData
class_name CornCharacter

func _init():
	character_name = "Corn"
	description = "A ranged specialist with kernel projectiles"
	base_health = 85.0
	base_speed = 5.5
	model_path = "res://models/characters/Corn.glb"
	color = Color(1.0, 0.8, 0.2)
	model_scale = 1.0  # Auto-normalized to the standard height
	model_origin_at_feet = true
	
	# Active ability: Kernel Barrage - shoots multiple projectiles
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Kernel Barrage"
	active_ability_data.description = "Fires a barrage of corn kernels in a cone"
	active_ability_data.cooldown = 7.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/KernelBarrage.gd"
	active_ability = active_ability_data
	
	# Passive ability: Sharp Kernels - increased ranged damage
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Sharp Kernels"
	passive_ability_data.description = "15% increased ranged weapon damage"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/RangedDamageBoost.gd"
	passive_ability = passive_ability_data
