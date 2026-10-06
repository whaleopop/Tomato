## Base class for all abilities
extends RefCounted
class_name Ability

var ability_name: String = ""
var description: String = ""
## Icon name for UITheme.icon (art/ui/icons, art/ui/kenney); "" = the HUD shows the initial letter
var icon: String = ""
var cooldown: float = 5.0
var enabled: bool = true
## True while replaying someone else's cast on a client (AbilityComponent.play_remote_cast):
## only the visuals matter - damage is server-only anyway, and moving the caster would fight
## the network interpolation of their position
var replay: bool = false

func _init(p_name: String = "", p_cooldown: float = 5.0):
	ability_name = p_name
	cooldown = p_cooldown

func initialize(entity):  # entity: Entity
	pass

func cleanup():
	pass

func update(delta: float, entity):  # entity: Entity
	pass
