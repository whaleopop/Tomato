## Resource defining weapon data
extends Resource
class_name WeaponData

@export var weapon_name: String = ""
@export var weapon_type: String = "melee"  # "melee" or "ranged"
@export var damage: float = 10.0
@export var range: float = 2.0
@export var cooldown: float = 0.5
@export var projectile_speed: float = 10.0  # For ranged weapons
@export var model_path: String = ""
@export var icon: Texture2D = null

