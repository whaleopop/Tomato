## Ranged weapon item with different weapon types
extends Weapon
class_name RangedWeapon

## New types go at the end: the number is sent over the network and stored in loot tables
enum WeaponType {
	PISTOL,
	SHOTGUN,
	SNIPER,
	RIFLE,
	FLAMETHROWER,
	SMG,
	HAND_CANNON,
	MARKSMAN,
	MINIGUN,
	DOUBLE_BARREL,
	JAM_BLASTER,
	LAUNCHER,
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
@export var visibility_range: float = 14.0  # World units the fog of war opens around you with it
@export var bullet_visibility_duration: float = 0.5  # How long bullet trail reveals area

# Shotgun specific
@export var pellet_count: int = 1  # Number of projectiles per shot
@export var spread_angle: float = 0.0  # Cone angle for spread

# Flamethrower specific
@export var burn_damage: float = 5.0  # Damage per second from fire
@export var burn_duration: float = 3.0  # How long fire lasts
@export var fire_trail_enabled: bool = false  # Leaves fire on ground

## How CombatComponent fires it: "single" (one hitscan bullet), "spread" (pellets in a cone),
## "pierce" (goes through the first target), "flame" (a cone of fire), "lob" (a grenade on an arc
## that blows up where it lands, blast_radius)
@export var fire_mode: String = "single"
@export var effect_style: String = "pistol"  # WeaponEffects tracer look: pistol / rifle / sniper
@export var move_factor: float = 1.0         # walking speed while it is in hand (heavy guns < 1)
@export var slow_on_hit: float = 0.0         # > 0: hit targets walk at this share of their speed...
@export var slow_time: float = 0.0           # ...for this long (StatusComponent "slow")
@export var blast_radius: float = 0.0        # "lob": damage around the landing spot

# Model (Kenney Blaster Kit, models/blaster-*.glb: the barrel points along -Z)
@export var model_path: String = ""
## How long the gun is in a hero's hands, in metres for a standard 1.2 m hero
## (WeaponVisualComponent fits the model to it, whatever size the file has)
@export var hold_length: float = 0.45

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
			weapon.visibility_range = 14.0
			weapon.bullet_visibility_duration = 0.3
			weapon.model_path = "res://models/pistol_1.glb"
			weapon.hold_length = 0.42

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
			weapon.visibility_range = 10.5
			weapon.bullet_visibility_duration = 0.2
			weapon.model_path = "res://models/shotgun_1.glb"
			weapon.hold_length = 0.8
			weapon.fire_mode = "spread"

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
			weapon.visibility_range = 26.0  # Best visibility
			weapon.bullet_visibility_duration = 1.0  # Long trail visibility
			weapon.model_path = "res://models/sniper_1.glb"
			weapon.hold_length = 0.95
			weapon.fire_mode = "pierce"
			weapon.effect_style = "sniper"

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
			weapon.visibility_range = 17.0
			weapon.bullet_visibility_duration = 0.4
			weapon.model_path = "res://models/rifle_1.glb"
			weapon.hold_length = 0.82
			weapon.effect_style = "rifle"

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
			weapon.visibility_range = 12.0
			weapon.bullet_visibility_duration = 0.8  # Fire illuminates area longer
			weapon.model_path = "res://models/fire_1.glb"
			weapon.hold_length = 0.75
			weapon.fire_mode = "flame"

		# ---- the Blaster Kit guns (models/blaster-*.glb)
		WeaponType.SMG:
			weapon.item_name = "SMG"
			weapon.ammo_type = AmmoItem.AmmoType.PISTOL
			weapon.damage = 9.0
			weapon.fire_rate = 0.07
			weapon.range = 20.0
			weapon.accuracy = 0.78
			weapon.magazine_size = 35
			weapon.current_ammo = 35
			weapon.reload_time = 1.8
			weapon.visibility_range = 12.0
			weapon.bullet_visibility_duration = 0.3
			weapon.model_path = "res://models/blaster-h.glb"
			weapon.hold_length = 0.55

		WeaponType.HAND_CANNON:
			weapon.item_name = "Hand Cannon"
			weapon.ammo_type = AmmoItem.AmmoType.PISTOL
			weapon.damage = 42.0
			weapon.fire_rate = 0.7
			weapon.range = 30.0
			weapon.accuracy = 0.98
			weapon.magazine_size = 6
			weapon.current_ammo = 6
			weapon.reload_time = 2.3
			weapon.visibility_range = 16.0
			weapon.bullet_visibility_duration = 0.5
			weapon.model_path = "res://models/blaster-b.glb"
			weapon.hold_length = 0.46
			weapon.effect_style = "sniper"

		WeaponType.MARKSMAN:
			weapon.item_name = "Marksman Rifle"
			weapon.ammo_type = AmmoItem.AmmoType.SNIPER
			weapon.damage = 40.0
			weapon.fire_rate = 0.45
			weapon.range = 55.0
			weapon.accuracy = 0.99
			weapon.magazine_size = 10
			weapon.current_ammo = 10
			weapon.reload_time = 2.6
			weapon.visibility_range = 21.0
			weapon.bullet_visibility_duration = 0.7
			weapon.model_path = "res://models/blaster-e.glb"
			weapon.hold_length = 0.95
			weapon.effect_style = "sniper"

		WeaponType.MINIGUN:
			weapon.item_name = "Minigun"
			weapon.ammo_type = AmmoItem.AmmoType.RIFLE
			weapon.damage = 9.0
			weapon.fire_rate = 0.05
			weapon.range = 30.0
			weapon.accuracy = 0.68
			weapon.magazine_size = 90
			weapon.current_ammo = 90
			weapon.reload_time = 4.5
			weapon.visibility_range = 15.0
			weapon.bullet_visibility_duration = 0.4
			weapon.model_path = "res://models/blaster-q.glb"
			weapon.hold_length = 0.85
			weapon.effect_style = "rifle"
			weapon.move_factor = 0.75

		WeaponType.DOUBLE_BARREL:
			weapon.item_name = "Double Barrel"
			weapon.ammo_type = AmmoItem.AmmoType.SHOTGUN
			weapon.damage = 11.0  # per pellet
			weapon.fire_rate = 0.3
			weapon.range = 12.0
			weapon.accuracy = 0.65
			weapon.magazine_size = 2
			weapon.current_ammo = 2
			weapon.reload_time = 2.0
			weapon.pellet_count = 10
			weapon.spread_angle = 32.0
			weapon.visibility_range = 10.5
			weapon.bullet_visibility_duration = 0.2
			weapon.model_path = "res://models/blaster-o.glb"
			weapon.hold_length = 0.65
			weapon.fire_mode = "spread"

		WeaponType.JAM_BLASTER:
			weapon.item_name = "Jam Blaster"
			weapon.ammo_type = AmmoItem.AmmoType.PISTOL
			weapon.damage = 11.0
			weapon.fire_rate = 0.18
			weapon.range = 24.0
			weapon.accuracy = 0.9
			weapon.magazine_size = 24
			weapon.current_ammo = 24
			weapon.reload_time = 2.0
			weapon.visibility_range = 13.0
			weapon.bullet_visibility_duration = 0.4
			weapon.model_path = "res://models/blaster-l.glb"
			weapon.hold_length = 0.6
			weapon.slow_on_hit = 0.55
			weapon.slow_time = 2.0

		WeaponType.LAUNCHER:
			weapon.item_name = "Grenade Launcher"
			weapon.ammo_type = AmmoItem.AmmoType.GRENADE
			weapon.damage = 45.0  # at the center of the blast, half at its edge
			weapon.fire_rate = 1.1
			weapon.range = 18.0
			weapon.accuracy = 1.0
			weapon.magazine_size = 4
			weapon.current_ammo = 4
			weapon.reload_time = 3.0
			weapon.visibility_range = 14.0
			weapon.bullet_visibility_duration = 0.8
			weapon.model_path = "res://models/blaster-k.glb"
			weapon.hold_length = 0.7
			weapon.fire_mode = "lob"
			weapon.blast_radius = 2.8

	return weapon

static var _modes: Dictionary = {}  # weapon type -> fire_mode

## How a weapon type fires, without keeping a weapon around (remote shot effects)
static func fire_mode_of(type: int) -> String:
	if not _modes.has(type):
		_modes[type] = create_weapon(type).fire_mode
	return _modes[type]

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
	return fire_mode == "flame"

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
