## Base class for all abilities
extends RefCounted
class_name Ability

var ability_name: String = ""
var description: String = ""
var cooldown: float = 5.0
var enabled: bool = true

func _init(p_name: String = "", p_cooldown: float = 5.0):
	ability_name = p_name
	cooldown = p_cooldown

func initialize(entity):  # entity: Entity
	pass

func cleanup():
	pass

func update(delta: float, entity):  # entity: Entity
	pass

