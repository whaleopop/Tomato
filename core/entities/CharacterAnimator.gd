## Makes character models feel alive.
## - Models without a skeleton get procedural "toy" animation: breathing, waddle + hop while
##   walking, lean into movement, stretch in the air, squash on landing, recoil, hit shake.
## - Models with an AnimationPlayer (rigged by tools/ai_models/rig_and_animate.py) play their
##   idle/walk/run/jump/attack/hit clips instead; the lean stays procedural on top.
## Speed is measured from the actual position change, so it works for the local player,
## remote players (network interpolation) and server-side entities alike.
extends Node
class_name CharacterAnimator

const WALK_CYCLE: float = 2.4       # steps per metre-ish
const HOP_HEIGHT: float = 0.07
const WADDLE_ANGLE: float = 0.14
const LEAN_ANGLE: float = 0.16
const BREATH_AMOUNT: float = 0.025
const RUN_SPEED: float = 6.5        # above this we play "run" instead of "walk"

var player: Node3D = null
var pivot: Node3D = null            # inserted between "Model" and the mesh instance
var anim_player: AnimationPlayer = null
var model_bottom: float = 0.0       # feet height in pivot space, so squash keeps feet planted

var _last_pos: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _vertical_speed: float = 0.0
var _airborne: bool = false
var _phase: float = 0.0
var _time: float = 0.0
var _squash: float = 0.0            # >0 squash, <0 stretch, decays
var _recoil: float = 0.0
var _shake: float = 0.0
var _dead: bool = false
var _current_clip: String = ""
# Spawn "drop-in": hidden for a short delay, then falls from above and lands with an impact
const SPAWN_DROP_TIME: float = 0.3
const SPAWN_DROP_HEIGHT: float = 3.0
var _spawn_delay: float = -1.0
var _spawn_t: float = -1.0
var _spawn_offset: float = 0.0
var _one_shot_until: float = 0.0
const HARD_LANDING_SPEED: float = 4.5   # m/s downwards; below that a landing doesn't shake tiles
var _fall_speed: float = 0.0            # fastest downward speed during the current airtime
# Idle variants: now and then a standing hero glances around / stretches / shifts weight (visual only)
const IDLE_VARIANTS: Array = ["idle_look", "idle_stretch", "idle_shift"]
var _idle_timer: float = randf_range(5.0, 12.0)
var _variant_until: float = -1.0
var _last_action_time: float = -100.0

func setup(p_player: Node3D):
	player = p_player
	_last_pos = player.global_position

	var combat = player.get_component("CombatComponent") if player.has_method("get_component") else null
	if combat:
		combat.shot_fired.connect(func(_a, _b, _c): on_attack())
	var abilities = player.get_component("AbilityComponent") if player.has_method("get_component") else null
	if abilities:
		abilities.ability_activated.connect(on_ability_cast)
	var health = player.get_component("HealthComponent") if player.has_method("get_component") else null
	if health:
		health.damage_taken.connect(func(_amount, _src): on_hit())
		health.died.connect(func(): _dead = true)

## Called every frame until the model exists (remote players get their model later)
func _bind() -> bool:
	var model = player.get_node_or_null("Model")
	if model:
		pivot = model.get_node_or_null("AnimPivot")
		if not pivot:
			var mesh = model.get_node_or_null("ModelMesh")
			if not mesh:
				return false
			pivot = Node3D.new()
			pivot.name = "AnimPivot"
			model.add_child(pivot)
			mesh.reparent(pivot, false)
		anim_player = _find_anim_player(pivot)
		if anim_player:
			# glTF has no loop flag: make the cycles loop
			for clip in ["idle", "walk", "run", "fall"]:
				if anim_player.has_animation(clip):
					anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		model_bottom = _bottom_of(pivot)
		return true

	var capsule = player.get_node_or_null("PlayerMesh")
	if capsule:
		pivot = capsule
		model_bottom = -0.6
		return true
	return false

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_anim_player(child)
		if found:
			return found
	return null

func _bottom_of(node: Node3D) -> float:
	var lowest = INF
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var aabb: AABB = mi.get_aabb()
		var local_xform = node.global_transform.affine_inverse() * mi.global_transform
		for i in 8:
			lowest = min(lowest, (local_xform * aabb.get_endpoint(i)).y)
	return lowest if lowest != INF else 0.0

## Drop the character in from above after `delay` seconds (used when a player appears)
func play_spawn(delay: float = 0.0):
	_spawn_delay = max(delay, 0.0)
	_spawn_t = -1.0
	if pivot:
		pivot.visible = false

func _update_spawn(delta: float):
	if _spawn_delay >= 0.0:
		pivot.visible = false
		_spawn_delay -= delta
		if _spawn_delay < 0.0:
			_spawn_t = 0.0
			pivot.visible = true
		return
	if _spawn_t < 0.0:
		_spawn_offset = 0.0
		return
	_spawn_t += delta
	var k = clamp(_spawn_t / SPAWN_DROP_TIME, 0.0, 1.0)
	_spawn_offset = (1.0 - k * k) * SPAWN_DROP_HEIGHT
	if k >= 1.0:
		_spawn_t = -1.0
		_spawn_offset = 0.0
		_squash = 1.0
		_play_one_shot("land")
		var color = player.character_data.color if player.get("character_data") else Color(1, 0.85, 0.6)
		LandingImpact.create_at(player.get_parent(), player.global_position, color.lerp(Color.WHITE, 0.4), 0.8)
		HexTile.shake_around(player, player.global_position, 1.0)
		if player.get("is_local_player"):
			var effects = get_node_or_null("/root/ScreenEffects")
			if effects and effects.has_method("shake"):
				effects.shake(0.25, 0.25)

func on_attack():
	_recoil = 1.0
	_play_one_shot("attack")

## Cast clip of the ability (also for replays on remote copies); models without it use "attack"
func on_ability_cast(ability) -> void:
	var pose: String = String(ability.get("cast_pose")) if ability else "attack"
	if not anim_player or not anim_player.has_animation(pose):
		pose = "attack"
	_play_one_shot(pose)

func on_hit():
	_shake = 1.0
	_squash = max(_squash, 0.5)
	_play_one_shot("hit")

func _process(delta: float):
	if not player or not is_instance_valid(player) or delta <= 0.0:
		return
	if not pivot or not is_instance_valid(pivot):
		if not _bind():
			return
	if _dead:
		return

	_time += delta
	_measure(delta)
	_update_spawn(delta)

	if anim_player and not anim_player.get_animation_list().is_empty():
		_drive_skeletal()
		_apply_lean_only(delta)
	else:
		_apply_procedural(delta)

func _measure(delta: float):
	var pos = player.global_position
	var d = pos - _last_pos
	_last_pos = pos
	if d.length() > 3.0:
		return  # teleport / network snap: ignore
	var horizontal = Vector2(d.x, d.z).length() / delta
	_speed = lerp(_speed, horizontal, 1.0 - exp(-delta * 12.0))
	_vertical_speed = lerp(_vertical_speed, d.y / delta, 1.0 - exp(-delta * 10.0))

	var was_airborne = _airborne
	_airborne = abs(_vertical_speed) > 1.5
	if _airborne:
		_fall_speed = max(_fall_speed, -_vertical_speed)
	elif was_airborne:
		_squash = 1.0  # landed
		if anim_player:
			_play_one_shot("land")
		# A real drop (jump, falling off a ledge) thuds the tiles; stepping down a tile does not
		if _fall_speed > HARD_LANDING_SPEED:
			HexTile.shake_around(player, player.global_position, clamp((_fall_speed - 3.0) / 10.0, 0.2, 0.8), 1.8)
		_fall_speed = 0.0

# ---------------------------------------------------------------- procedural

func _apply_procedural(delta: float):
	var moving = clamp(_speed / 5.0, 0.0, 1.3)
	_phase += _speed * delta * WALK_CYCLE

	var hop = abs(sin(_phase)) * HOP_HEIGHT * moving
	var waddle = sin(_phase) * WADDLE_ANGLE * moving
	var breath = sin(_time * 2.4) * BREATH_AMOUNT * (1.0 - clamp(moving, 0.0, 1.0))

	# Footfall squash on every step, plus landing / hit impulses that spring back
	var step_squash = (1.0 - abs(sin(_phase))) * 0.06 * moving
	_squash = move_toward(_squash, 0.0, delta * 4.0)
	var squash = step_squash + _squash * 0.22
	if _airborne:
		squash = -0.08 if _vertical_speed > 0.0 else -0.04  # stretch in the air

	var sy = 1.0 + breath - squash
	var sxz = 1.0 - breath * 0.5 + squash * 0.5

	var lean = _lean_vector()
	_recoil = move_toward(_recoil, 0.0, delta * 6.0)
	_shake = move_toward(_shake, 0.0, delta * 5.0)
	var shake_rot = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.12 * _shake

	pivot.scale = Vector3(sxz, sy, sxz)
	# Keep the feet on the ground while scaling around the pivot
	pivot.position = Vector3(0, model_bottom * (1.0 - sy) + hop + _spawn_offset, 0)
	pivot.rotation = Vector3(lean.x - _recoil * 0.25, 0, waddle + lean.y) + shake_rot

## Pitch/roll that tilts the character into its movement direction (local space)
func _lean_vector() -> Vector2:
	var basis_inv = player.global_transform.basis.inverse()
	var dir = Vector3(sin(player.rotation.y), 0, cos(player.rotation.y))
	var movement = player.get_component("MovementComponent") if player.has_method("get_component") else null
	if movement and movement.velocity.length() > 0.1:
		dir = Vector3(movement.velocity.x, 0, movement.velocity.z).normalized()
	elif _speed < 0.2:
		return Vector2.ZERO
	var local_dir = basis_inv * dir
	var amount = clamp(_speed / 7.0, 0.0, 1.0) * LEAN_ANGLE
	return Vector2(local_dir.z * amount, -local_dir.x * amount)

# ---------------------------------------------------------------- skeletal

func _drive_skeletal():
	if _variant_until >= 0.0:
		# an idle variant is playing: cut it as soon as the hero moves, falls or acts
		if _time >= _variant_until or _speed > 0.4 or _airborne or _time < _one_shot_until:
			_variant_until = -1.0
			_current_clip = ""
		else:
			return
	if _time < _one_shot_until:
		return
	var clip = "idle"
	if _airborne:
		clip = "fall" if _vertical_speed < 0.0 and anim_player.has_animation("fall") else "jump"
	elif _speed > RUN_SPEED:
		clip = "run"
	elif _speed > 0.4:
		clip = "walk"
	if not anim_player.has_animation(clip):
		clip = "walk" if clip == "run" and anim_player.has_animation("walk") else "idle"
	if not anim_player.has_animation(clip):
		return
	if clip == "idle":
		_idle_timer -= get_process_delta_time()
		if _idle_timer <= 0.0:
			_idle_timer = randf_range(5.0, 12.0)
			# not while fighting (shot / cast / hit in the last 4 s) and never on a headless server
			if _time - _last_action_time > 4.0 and DisplayServer.get_name() != "headless" and not _holds_ranged_weapon():
				var v: String = IDLE_VARIANTS[randi() % IDLE_VARIANTS.size()]
				if anim_player.has_animation(v):
					anim_player.play(v, 0.3)
					anim_player.speed_scale = 1.0
					_current_clip = v
					_variant_until = _time + anim_player.get_animation(v).length
					return
	if clip != _current_clip:
		_current_clip = clip
		anim_player.play(clip, 0.15)
	# Walk cycle speed follows the actual movement speed
	if clip == "walk" or clip == "run":
		anim_player.speed_scale = clamp(_speed / (RUN_SPEED if clip == "run" else 3.5), 0.6, 1.8)
	else:
		anim_player.speed_scale = 1.0

func _holds_ranged_weapon() -> bool:
	var combat = player.get_component("CombatComponent") if player and player.has_method("get_component") else null
	return combat != null and combat.get("equipped_ranged_weapon") != null

func _play_one_shot(clip: String):
	if not anim_player or not anim_player.has_animation(clip):
		return
	anim_player.play(clip, 0.08)
	_last_action_time = _time
	anim_player.speed_scale = 1.0
	_current_clip = clip
	_one_shot_until = _time + anim_player.get_animation(clip).length * 0.9

func _apply_lean_only(delta: float):
	var lean = _lean_vector()
	_recoil = move_toward(_recoil, 0.0, delta * 6.0)
	pivot.rotation = Vector3(lean.x * 0.6 - _recoil * 0.12, 0, lean.y * 0.6)
	# Landing squash also for rigged models (their clips don't scale the whole body)
	_squash = move_toward(_squash, 0.0, delta * 4.0)
	var sy = 1.0 - _squash * 0.25
	pivot.scale = Vector3(1.0 + _squash * 0.12, sy, 1.0 + _squash * 0.12)
	pivot.position = Vector3(0, model_bottom * (1.0 - sy) + _spawn_offset, 0)
