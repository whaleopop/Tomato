## Ranged weapon item with different weapon types
extends Weapon
class_name RangedWeapon

enum WeaponType {
	PISTOL,
	SHOTGUN,
	SNIPER,
	RIFLE,
	FLAMETHROWER
}

@export var weapon_type: WeaponType = WeaponType.PISTOL
@export var ammo_type: AmmoItem.AmmoType = AmmoItem.AmmoType.PISTOL
@export var current_ammo: int = 12
@export var magazine_size: int = 12
@export var reload_time: float = 2.0
@export var is_reloading: bool = false

# Combat stats
@export var damage: float = 15.0
@export var fire_rate: float = 0.3  # Seconds between shots
@export var range: float = 30.0  # Max range in units
@export var projectile_speed: float = 50.0
@export var accuracy: float = 1.0  # 1.0 = perfect, lower = more spread

# Visibility stats (for fog of war)
@export var visibility_range: float = 8.0  # How far player can see with this weapon
@export var bullet_visibility_duration: float = 0.5  # How long bullet trail reveals area

# Shotgun specific
@export var pellet_count: int = 1  # Number of projectiles per shot
@export var spread_angle: float = 0.0  # Cone angle for spread

# Flamethrower specific
@export var burn_damage: float = 5.0  # Damage per second from fire
@export var burn_duration: float = 3.0  # How long fire lasts
@export var fire_trail_enabled: bool = false  # Leaves fire on ground

# Model path
@export var model_path: String = ""

func _init():
	item_name = "Ranged Weapon"
	consumable = false
	stackable = false

## Create a specific weapon type with preset stats
static func create_weapon(type: WeaponType) -> RangedWeapon:
	var weapon = RangedWeapon.new()
	weapon.weapon_type = type

	match type:
		WeaponType.PISTOL:
			weapon.item_name = "Pistol"
			weapon.ammo_type = AmmoItem.AmmoType.PISTOL
			weapon.damage = 15.0
			weapon.fire_rate = 0.25
			weapon.range = 25.0
			weapon.projectile_speed = 60.0
			weapon.accuracy = 0.95
			weapon.magazine_size = 12
			weapon.current_ammo = 12
			weapon.reload_time = 1.5
			weapon.visibility_range = 8.0
			weapon.bullet_visibility_duration = 0.3
			weapon.model_path = "res://models/pistol_1.glb"

		WeaponType.SHOTGUN:
			weapon.item_name = "Shotgun"
			weapon.ammo_type = AmmoItem.AmmoType.SHOTGUN
			weapon.damage = 12.0  # Per pellet
			weapon.fire_rate = 0.8
			weapon.range = 15.0
			weapon.projectile_speed = 45.0
			weapon.accuracy = 0.7
			weapon.magazine_size = 6
			weapon.current_ammo = 6
			weapon.reload_time = 2.5
			weapon.pellet_count = 8
			weapon.spread_angle = 25.0
			weapon.visibility_range = 6.0
			weapon.bullet_visibility_duration = 0.2
			weapon.model_path = "res://models/shotgun_1.glb"

		WeaponType.SNIPER:
			weapon.item_name = "Sniper Rifle"
			weapon.ammo_type = AmmoItem.AmmoType.SNIPER
			weapon.damage = 85.0
			weapon.fire_rate = 1.5
			weapon.range = 80.0
			weapon.projectile_speed = 120.0
			weapon.accuracy = 1.0
			weapon.magazine_size = 5
			weapon.current_ammo = 5
			weapon.reload_time = 3.5
			weapon.visibility_range = 15.0  # Best visibility
			weapon.bullet_visibility_duration = 1.0  # Long trail visibility
			weapon.model_path = "res://models/sniper_1.glb"

		WeaponType.RIFLE:
			weapon.item_name = "Assault Rifle"
			weapon.ammo_type = AmmoItem.AmmoType.RIFLE
			weapon.damage = 18.0
			weapon.fire_rate = 0.1  # Fast fire rate
			weapon.range = 40.0
			weapon.projectile_speed = 70.0
			weapon.accuracy = 0.85
			weapon.magazine_size = 30
			weapon.current_ammo = 30
			weapon.reload_time = 2.0
			weapon.visibility_range = 10.0
			weapon.bullet_visibility_duration = 0.4
			weapon.model_path = "res://models/rifle_1.glb"

		WeaponType.FLAMETHROWER:
			weapon.item_name = "Flamethrower"
			weapon.ammo_type = AmmoItem.AmmoType.FUEL
			weapon.damage = 8.0  # Direct hit damage
			weapon.fire_rate = 0.05  # Continuous stream
			weapon.range = 12.0
			weapon.projectile_speed = 20.0
			weapon.accuracy = 0.6
			weapon.magazine_size = 100
			weapon.current_ammo = 100
			weapon.reload_time = 4.0
			weapon.burn_damage = 5.0
			weapon.burn_duration = 3.0
			weapon.fire_trail_enabled = true
			weapon.visibility_range = 7.0
			weapon.bullet_visibility_duration = 0.8  # Fire illuminates area longer
			weapon.model_path = "res://models/fire_1.glb"

	return weapon

## Check if weapon can shoot
func can_shoot() -> bool:
	return current_ammo > 0 and not is_reloading

## Consume ammo for one shot
func consume_ammo() -> bool:
	if current_ammo > 0:
		current_ammo -= 1
		return true
	return false

## Start reload process
func start_reload(reserve_ammo: int) -> int:
	if is_reloading or current_ammo == magazine_size:
		return 0

	var ammo_needed = magazine_size - current_ammo
	var ammo_to_reload = mini(ammo_needed, reserve_ammo)

	if ammo_to_reload > 0:
		is_reloading = true
		return ammo_to_reload

	return 0

## Complete reload
func complete_reload(ammo_amount: int):
	current_ammo += ammo_amount
	current_ammo = mini(current_ammo, magazine_size)
	is_reloading = false

## Get ammo display text
func get_ammo_display() -> String:
	return "%d / %d" % [current_ammo, magazine_size]

## Get spread directions for shotgun/spread weapons
func get_spread_directions(forward: Vector3) -> Array[Vector3]:
	var directions: Array[Vector3] = []

	if pellet_count <= 1:
		directions.append(forward)
		return directions

	var spread_rad = deg_to_rad(spread_angle)

	for i in range(pellet_count):
		var angle_offset = randf_range(-spread_rad, spread_rad)
		var vertical_offset = randf_range(-spread_rad * 0.5, spread_rad * 0.5)

		# Rotate forward vector by random angles
		var right = forward.cross(Vector3.UP).normalized()
		var up = right.cross(forward).normalized()

		var spread_dir = forward
		spread_dir = spread_dir.rotated(up, angle_offset)
		spread_dir = spread_dir.rotated(right, vertical_offset)

		directions.append(spread_dir.normalized())

	return directions

## Check if this is a continuous fire weapon (flamethrower)
func is_continuous_fire() -> bool:
	return weapon_type == WeaponType.FLAMETHROWER

## Get weapon description
func get_description() -> String:
	var desc = "%s\n" % item_name
	desc += "Damage: %.0f\n" % damage
	desc += "Range: %.0f\n" % range
	desc += "Fire Rate: %.2f/s\n" % (1.0 / fire_rate)

	if pellet_count > 1:
		desc += "Pellets: %d\n" % pellet_count

	if fire_trail_enabled:
		desc += "Burn: %.0f/s for %.1fs\n" % [burn_damage, burn_duration]

	return desc
