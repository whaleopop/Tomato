## Puts a hero's arms on the gun it carries: runs on the Skeleton3D after the AnimationMixer and
## aims the right arm bone (the one at -X; picked by rest position, not by name) at the grip and the
## left one at the foregrip, stretching it a little to reach. All points live on the weapon holder
## node, so recoil and the reload dip drag the hands along. Bones' +Y runs along the arm.
## Visual only: never created on a headless server.
extends SkeletonModifier3D
class_name WeaponGripModifier

enum Grip { NONE, ONE_HAND, SHOULDER, HEAVY_HIP }

const ARM_LENGTH: float = 0.38      # a leaf arm bone, in the model's own units
const STRETCH_MIN: float = 0.85
const STRETCH_MAX: float = 1.25
const STRETCH_MAX_LEFT: float = 1.6
const FADE_SPEED: float = 8.0       # influence per second
const MAG_SPEED: float = 4.0        # the left hand to the magazine and back

var player: Node3D = null
var holder: Node3D = null            # the weapon node the hands follow
var grip: int = Grip.NONE
var right_local: Vector3 = Vector3.ZERO      # in the holder's space
var left_local: Vector3 = Vector3.ZERO
var mag_local: Vector3 = Vector3.ZERO
var reloading: bool = false
var enabled_grip: bool = true        # false during casts / death
var right_bone: int = -1
var left_bone: int = -1
var stats: Dictionary = {}           # bone -> (wanted stretch, used stretch, tip miss); read by tests
var _mag: float = 0.0
var _mag_step: int = 0               # 0 idle, 1 reach, 2 hold, 3 back
var _hold_left: float = 0.0

## Finds the arm bones; false when the rig has none
func bind(skel: Skeleton3D, p_player: Node3D) -> bool:
	player = p_player
	right_bone = -1
	left_bone = -1
	var best_r := INF
	var best_l := -INF
	var to_player: Transform3D = player.global_transform.affine_inverse() * skel.global_transform
	for i in skel.get_bone_count():
		if not skel.get_bone_name(i).to_lower().contains("arm"):
			continue
		var x: float = (to_player * skel.get_bone_global_rest(i).origin).x
		if x < best_r:
			best_r = x
			right_bone = i
		if x > best_l:
			best_l = x
			left_bone = i
	if right_bone == left_bone:
		left_bone = -1
	return right_bone >= 0

func set_weapon(p_holder: Node3D, weapon_type: int, length: float, hero_scale: float) -> void:
	holder = p_holder
	if holder == null:
		grip = Grip.NONE
		return
	match weapon_type:
		RangedWeapon.WeaponType.PISTOL, RangedWeapon.WeaponType.HAND_CANNON:
			grip = Grip.ONE_HAND
		RangedWeapon.WeaponType.MINIGUN, RangedWeapon.WeaponType.FLAMETHROWER, RangedWeapon.WeaponType.LAUNCHER:
			grip = Grip.HEAVY_HIP
		_:
			grip = Grip.SHOULDER
	# Holder origin = the middle of the gun; the hand sits GRIP behind it (barrel along +Z here)
	right_local = Vector3(0, 0, -length * WeaponVisualComponent.GRIP)
	left_local = right_local + Vector3(0.12 * hero_scale, 0, length * 0.15)
	mag_local = Vector3(0, -0.15 * hero_scale, -length * 0.1)

func start_reload() -> void:
	reloading = true
	_mag_step = 1

func end_reload() -> void:
	reloading = false

## Where the right hand should be, in the player's space (for tests / debugging)
func right_target() -> Vector3:
	return _to_player(right_local)

func _to_player(local: Vector3) -> Vector3:
	return player.global_transform.affine_inverse() * (holder.global_transform * local)

func _process(delta: float) -> void:
	var want := 1.0 if (enabled_grip and grip != Grip.NONE and holder != null and is_instance_valid(holder)) else 0.0
	influence = move_toward(influence, want, FADE_SPEED * delta)
	# Reload: reach the magazine, hold a beat, come back
	match _mag_step:
		1:
			_mag = move_toward(_mag, 1.0, MAG_SPEED * delta)
			if _mag >= 1.0:
				_mag_step = 2
				_hold_left = 0.2
		2:
			if not reloading:
				_hold_left -= delta
				if _hold_left <= 0.0:
					_mag_step = 3
		3:
			_mag = move_toward(_mag, 0.0, MAG_SPEED * delta)
			if _mag <= 0.0:
				_mag_step = 0

func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or player == null or holder == null or not is_instance_valid(holder) or grip == Grip.NONE:
		return
	var to_skel: Transform3D = skel.global_transform.affine_inverse() * player.global_transform
	if right_bone >= 0:
		_aim(skel, right_bone, to_skel * _to_player(right_local), STRETCH_MAX)
	if left_bone >= 0 and grip != Grip.ONE_HAND:
		var target := _to_player(left_local).lerp(_to_player(mag_local), _mag)
		_aim(skel, left_bone, to_skel * target, STRETCH_MAX_LEFT)

## Turn the bone so its +Y points at `target` (skeleton space), stretched to reach it
func _aim(skel: Skeleton3D, bone: int, target: Vector3, max_stretch: float) -> void:
	var g: Transform3D = skel.get_bone_global_pose(bone)
	var b := g.basis.orthonormalized()
	var to := target - g.origin
	var dist := to.length()
	if dist < 0.001:
		return
	b = Basis(Quaternion(b.y, to / dist)) * b
	var length := bone_length(skel, bone)
	var scale_y := clampf(dist / length, STRETCH_MIN, max_stretch)
	var origin := g.origin
	if dist < length * scale_y:
		# Too close for a natural arm: keep its length and slide it back along its axis, so the
		# hand stays on the grip and the extra length sinks into the body (no squeezed stub)
		origin = target - (to / dist) * length * scale_y
	# Stretch clamped and the hand still short: lean the whole arm out a little (at most 11 cm)
	var short := dist - length * scale_y
	if short > 0.0 and dist >= length * scale_y:
		origin += (to / dist) * minf(short, 0.11)
	# Stretched arms get thinner (volume), so a long reach is not a fat fist
	var girth := clampf(1.0 / sqrt(scale_y), 0.8, 1.0) if scale_y > 1.0 else 1.0
	b = b.scaled_local(Vector3(girth, scale_y, girth))
	skel.set_bone_global_pose(bone, Transform3D(b, origin))
	stats[bone] = Vector3(dist / length, scale_y, (origin + (to / dist) * length * scale_y - target).length())  # raw stretch, used stretch, miss (tests)

## Distance to the child bone when there is one (leaf arm bones use ARM_LENGTH, measured on the heroes)
func bone_length(skel: Skeleton3D, bone: int) -> float:
	var kids := skel.get_bone_children(bone)
	if kids.is_empty():
		return ARM_LENGTH
	return maxf(skel.get_bone_rest(kids[0]).origin.length(), 0.05)
