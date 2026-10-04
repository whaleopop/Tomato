## Hostile weeds that roam the island (WeedSpawner puts them there): Dandelion throws seed puffs
## from a distance, Hogweed is a slow, tough brute whose sap burns and slows, Nettle is quick and
## stings. On the server (`authority`) they think: pick the nearest visible hero in AGGRO range,
## chase within LEASH of home, hit, go home to heal. Clients get a copy (`authority` false) that only
## follows the server's state (TickSystem "npcs" -> ClientWorld._apply_npcs) and plays the clips;
## the host sees the server's own weeds. Shot like players (HitscanSystem -> get_component
## ("HealthComponent")), damage only counts on the server. entity_id is negative (never a peer id).
extends CharacterBody3D
class_name Weed

## Per kind: name (an id, translated for display), model, look and fight
const KINDS = {
	"Dandelion": {"model": "res://models/enemies/dandelion.glb", "height": 1.35, "color": Color(1.0, 0.82, 0.2),
		"health": 70.0, "speed": 3.2, "damage": 14.0, "range": 11.0, "keep": 7.5, "cooldown": 1.8, "aggro": 16.0,
		"style": "seed", "slow": 0.0},
	"Hogweed": {"model": "res://models/enemies/hogweed.glb", "height": 1.9, "color": Color(0.95, 0.93, 0.8),
		"health": 170.0, "speed": 2.6, "damage": 22.0, "range": 2.1, "keep": 0.0, "cooldown": 1.6, "aggro": 13.0,
		"style": "melee", "slow": 0.55, "burn": 3.0},
	"Nettle": {"model": "res://models/enemies/nettle.glb", "height": 1.3, "color": Color(0.35, 0.75, 0.3),
		"health": 90.0, "speed": 5.2, "damage": 9.0, "range": 1.7, "keep": 0.0, "cooldown": 0.8, "aggro": 14.0,
		"style": "melee", "slow": 0.75},
}
const LEASH: float = 28.0           # from home: further than this they give up and go back
const GRAVITY: float = 25.0
const SEED_FLIGHT: float = 0.75     # seconds a dandelion seed puff flies (dodgeable)
const SEED_RADIUS: float = 1.3
const THINK_EVERY: float = 0.25
const HEAL_PER_SECOND: float = 12.0 # going home they grow back
const LOOT_CHANCE: float = 0.55     # something drops when they die

var npc_id: int = 0
var entity_id: int = 0              # -npc_id: shot / hit code reads it like a player's
var kind: String = "Dandelion"
var authority: bool = true
var health: HealthComponent
var home: Vector3 = Vector3.ZERO
var anim_state: String = "idle"     # idle / walk / attack / hit / death (synced to clients)
## Weed Swarm (SurvivorsRules): goes for the nearest hero anywhere, never goes home
var hunter: bool = false

var _target: Node3D = null
var _think: float = 0.0
var _cooldown: float = 0.0
var _windup: float = -1.0
var _wander_to: Vector3 = Vector3.ZERO
var _wander_wait: float = 0.0
var _model: Node3D
var _anim: AnimationPlayer
var _bar_fill: MeshInstance3D
var _bar_root: Node3D
var _bob: float = 0.0
var _dead_time: float = -1.0
var _net_pos: Vector3 = Vector3.ZERO
var _net_yaw: float = 0.0
var _zone_check: float = 0.0
var _rng := RandomNumberGenerator.new()

func cfg() -> Dictionary:
	return KINDS.get(kind, KINDS["Dandelion"])

func _ready():
	add_to_group("npcs")
	entity_id = -npc_id
	collision_layer = HitscanSystem.LAYER_ENEMIES
	collision_mask = HitscanSystem.LAYER_ENVIRONMENT | HitscanSystem.LAYER_PLAYERS
	floor_snap_length = 0.4
	var shape = CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = cfg().height * 0.9
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = shape.height / 2.0
	add_child(col)
	health = HealthComponent.new(self, cfg().health)
	health.died.connect(_on_died)
	health.damage_taken.connect(_on_hurt)
	_rng.seed = npc_id * 7919
	_build_look()
	home = global_position
	_net_pos = global_position
	_wander_to = home

func get_component(component_name: String):
	return health if component_name == "HealthComponent" else null

## Show name: "Dandelion" -> the translated name
func display_name() -> String:
	return Locale.t(kind)

# ---------------------------------------------------------------- looks

func _build_look():
	_model = Node3D.new()
	add_child(_model)
	var c = cfg()
	if ResourceLoader.exists(c.model):
		var inst = load(c.model).instantiate()
		ModelUtils.apply_lowpoly_look(inst)
		_model.add_child(inst)
		ModelUtils.normalize_to_height(inst, c.height)
		var players = inst.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			_anim = players[0]
			for clip in ["idle", "walk", "run"]:
				if _anim.has_animation(clip):
					_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	else:
		var mesh = MeshInstance3D.new()
		var cap = CapsuleMesh.new()
		cap.radius = 0.35
		cap.height = c.height
		mesh.mesh = cap
		var mat = StandardMaterial3D.new()
		mat.albedo_color = c.color
		mesh.material_override = mat
		mesh.position.y = c.height / 2.0
		_model.add_child(mesh)
	# A health bar over the head (only while hurt) with the name
	_bar_root = Node3D.new()
	_bar_root.position.y = c.height + 0.35
	_bar_root.visible = false
	add_child(_bar_root)
	_bar_root.add_child(_bar_quad(Vector2(1.0, 0.11), Color(0.05, 0.05, 0.08, 0.8), 0.0))
	_bar_fill = _bar_quad(Vector2(0.96, 0.07), Color(1.0, 0.35, 0.3), 0.001)
	_bar_root.add_child(_bar_fill)
	var label = Label3D.new()
	label.text = kind
	label.font = UITheme.font_black()
	label.font_size = 36
	label.outline_size = 8
	label.pixel_size = 0.005
	label.modulate = c.color.lightened(0.3)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.18
	_bar_root.add_child(label)

func _bar_quad(size: Vector2, color: Color, lift: float) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var q = QuadMesh.new()
	q.size = size
	q.center_offset = Vector3(size.x / 2.0, 0, lift)  # grows from the left edge
	mi.mesh = q
	mi.position.x = -size.x / 2.0
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	mat.render_priority = 5
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _play(clip: String):
	anim_state = clip
	if not _anim:
		return
	var clip_name = clip
	if clip == "walk" and kind == "Nettle" and _anim.has_animation("run"):
		clip_name = "run"
	if _anim.has_animation(clip_name) and _anim.current_animation != clip_name:
		_anim.play(clip_name, 0.15)

func _update_bar():
	var hp = health.current_health / max(health.max_health, 1.0)
	_bar_root.visible = hp < 0.999 and hp > 0.0
	_bar_fill.scale.x = max(hp, 0.001)

# ---------------------------------------------------------------- server: thinking

func _physics_process(delta: float):
	if _dead_time >= 0.0:
		_dead_time += delta
		_model.scale = Vector3.ONE * max(0.01, 1.0 - _dead_time * 0.8)
		if authority and _dead_time > 2.0:
			queue_free()
		return
	_update_bar()
	if not authority:
		_follow_network(delta)
		return
	_cooldown = max(0.0, _cooldown - delta)
	_think -= delta
	if _think <= 0.0:
		_think = THINK_EVERY
		_pick_target()
	_zone_check -= delta
	if _zone_check <= 0.0:
		_zone_check = 0.5
		_check_ground()

	var c = cfg()
	var want := Vector3.ZERO
	if _windup >= 0.0:
		_windup += delta
		if _windup >= 0.35:
			_windup = -1.0
			_strike()
	elif _target:
		var to = _target.global_position - global_position
		to.y = 0.0
		var dist = to.length()
		_face(to)
		if dist <= c.range and _cooldown <= 0.0 and _sees(_target):
			_cooldown = c.cooldown
			_windup = 0.0
			_play("attack")
		elif dist > c.range * 0.85 or (c.keep > 0.0 and dist > c.keep):
			want = to.normalized() * c.speed
		elif c.keep > 0.0 and dist < c.keep * 0.6:
			want = -to.normalized() * c.speed * 0.7  # dandelions back off
	else:
		# Home: walk back, heal up, wander a little
		var to_home = home - global_position
		to_home.y = 0.0
		if to_home.length() > 6.0:
			want = to_home.normalized() * c.speed
			_face(to_home)
		else:
			_wander_wait -= delta
			var to_spot = _wander_to - global_position
			to_spot.y = 0.0
			if to_spot.length() > 0.6 and _wander_wait <= 0.0:
				want = to_spot.normalized() * c.speed * 0.4
				_face(to_spot)
			elif _wander_wait <= 0.0:
				_wander_wait = _rng.randf_range(2.0, 5.0)
				var a = _rng.randf() * TAU
				_wander_to = home + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(1.0, 4.0)
		if health.current_health < health.max_health:
			health.heal(HEAL_PER_SECOND * delta)

	var status_slow = 1.0
	velocity.x = want.x * status_slow
	velocity.z = want.z * status_slow
	if is_on_floor():
		velocity.y = 0.0
		if is_on_wall() and want.length_squared() > 0.1:
			velocity.y = 7.5  # hop up a ledge
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if _windup < 0.0:
		_play("walk" if want.length_squared() > 0.1 else "idle")
	if not _anim:
		_procedural(delta, want.length_squared() > 0.1)

func _face(dir: Vector3):
	if dir.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 0.25)  # heroes and weeds face +Z

func _pick_target():
	var c = cfg()
	var best: Node3D = null
	var best_d = INF
	var from_home = global_position.distance_to(home)
	for p in get_tree().get_nodes_in_group("players"):
		if not (p is Player) or p.has_meta("training_dummy") or not p.is_inside_tree():
			continue
		var h = p.get_component("HealthComponent")
		if not h or h.is_dead:
			continue
		if hunter:
			var dh = p.global_position.distance_to(global_position)
			if dh < best_d:
				best = p
				best_d = dh
			continue
		var status = p.get_component("StatusComponent")
		if status and status.is_stealthed():
			continue
		var d = p.global_position.distance_to(global_position)
		var reach = c.aggro * (1.6 if p == _target else 1.0)  # keep chasing a bit further
		if d < reach and d < best_d and p.global_position.distance_to(home) < LEASH and _sees(p):
			best = p
			best_d = d
	if from_home > LEASH and not hunter:
		best = null  # too far from home: go back
	_target = best

func _sees(p: Node3D) -> bool:
	return not CoverSpawner.fire_blocked(get_world_3d(), global_position + Vector3(0, 1.0, 0), p.global_position + Vector3(0, 0.9, 0))

func _strike():
	if not _target or not is_instance_valid(_target):
		return
	var c = cfg()
	if c.style == "seed":
		_throw_seed(_target.global_position + Vector3(0, 0.2, 0))
		return
	var to = _target.global_position - global_position
	to.y = 0.0
	AbilityFX.slash(self, to.normalized(), c.range, 100.0, c.color)
	if to.length() > c.range + 0.6:
		return  # stepped away in time
	_hurt(_target, c.damage)

func _hurt(p: Node3D, amount: float):
	var c = cfg()
	var h = p.get_component("HealthComponent")
	if not h:
		return
	h.take_damage(amount, self)
	var status = p.get_component("StatusComponent")
	if status and c.slow > 0.0:
		status.apply("slow", 1.5, c.slow)
	# Hogweed's sap keeps burning a moment
	if c.has("burn"):
		for i in 3:
			get_tree().create_timer(0.8 * (i + 1)).timeout.connect(func():
				if is_instance_valid(p) and p.get_component("HealthComponent") and not p.get_component("HealthComponent").is_dead:
					p.get_component("HealthComponent").take_damage(c.burn, self))

## Dandelion: a puff of seeds flies to where the hero stands now; whoever is still there gets it
func _throw_seed(to: Vector3):
	var from = global_position + Vector3(0, cfg().height * 0.8, 0)
	play_seed(from, to)
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.has_method("broadcast_npc_seed"):
		nm.broadcast_npc_seed(from, to)
	get_tree().create_timer(SEED_FLIGHT).timeout.connect(func():
		if not is_inside_tree():
			return
		for p in get_tree().get_nodes_in_group("players"):
			if p is Player and not p.has_meta("training_dummy") and p.global_position.distance_to(to) < SEED_RADIUS:
				_hurt(p, cfg().damage))

## The seed puff's flight and landing (every peer that sees it)
static func play_seed(from: Vector3, to: Vector3, parent: Node = null) -> void:
	var host = parent if parent else Engine.get_main_loop().current_scene
	if not host:
		return
	var anchor = Node3D.new()
	host.add_child(anchor)
	AbilityFX.throw_blob(anchor, from, to, Color(1.0, 0.95, 0.75), SEED_FLIGHT)
	Sfx.at("weed_spit", from)
	anchor.get_tree().create_timer(SEED_FLIGHT).timeout.connect(func():
		if is_instance_valid(anchor):
			AbilityFX.splash(anchor, to, Color(1.0, 0.92, 0.5), SEED_RADIUS)
			anchor.get_tree().create_timer(2.0).timeout.connect(anchor.queue_free))

## The zone and the rim: a weed on burning ground withers, one swallowed by a mountain is gone
func _check_ground():
	var grid = _grid()
	if not grid:
		return
	var tile = grid.get_tile(grid.world_to_hex(global_position))
	if tile == null or tile.is_destroyed or tile.biome_type == HexTile.BiomeType.MOUNTAIN:
		health.take_damage(health.max_health, null)
	elif tile.zone_state == HexTile.ZoneState.BURNING:
		health.take_damage(12.0, null)
	if global_position.y < -10.0:
		health.take_damage(health.max_health, null)

func _grid() -> HexGrid:
	var n = get_parent()
	while n:
		if "hex_grid" in n and n.hex_grid is HexGrid:
			return n.hex_grid
		if "grid" in n and n.grid is HexGrid:
			return n.grid
		n = n.get_parent()
	return null

func _on_hurt(amount: float, source):
	if amount > 0.0:
		AbilityFX.number(self, -amount, Color(1.0, 0.9, 0.5))
	# Shot from out of its range: it comes after you
	if authority and is_instance_valid(source) and source is Player and not source.has_meta("training_dummy"):
		_target = source

func _on_died():
	_dead_time = 0.0
	_play("death")
	if not withered:
		Sfx.at("weed_die", global_position)
	collision_layer = 0
	_bar_root.visible = false
	if authority and not withered:
		_credit_kill()
		_drop_loot()
	if GameModes.current() == GameModes.SURVIVORS and not withered:
		_xp_orb()

## Weed Swarm: the wave is over and what is left of it shrivels away (no loot, nobody's kill)
var withered: bool = false
func wither() -> void:
	withered = true
	health.last_attacker = null
	health.die()

## Whoever felled it (Weed Swarm coins: ServerPlayer.weed_kills)
func _credit_kill():
	var killer = health.last_attacker
	if not is_instance_valid(killer) or not (killer is Player):
		return
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.game_server and nm.game_server.players.has(killer.entity_id):
		nm.game_server.players[killer.entity_id].weed_kills += 1

## Weed Swarm: a glowing bit of XP flies from the fallen weed to the nearest hero (looks only)
func _xp_orb():
	var best: Node3D = null
	var best_d = INF
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node3D and p.visible and p.global_position.distance_to(global_position) < best_d:
			best = p
			best_d = p.global_position.distance_to(global_position)
	if best == null or get_parent() == null:
		return
	var orb = MeshInstance3D.new()
	var ball = SphereMesh.new()
	ball.radius = 0.16
	ball.height = 0.32
	orb.mesh = ball
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 1.0, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 1.0, 0.45)
	mat.emission_energy_multiplier = 3.0
	orb.material_override = mat
	get_parent().add_child(orb)
	var from = global_position + Vector3(0, 1.0, 0)
	orb.global_position = from
	var target = best
	var t = orb.create_tween()
	t.tween_method(func(k: float):
		if is_instance_valid(orb) and is_instance_valid(target):
			var to = target.global_position + Vector3(0, 0.9, 0)
			orb.global_position = from.lerp(to, k * k) + Vector3(0, sin(k * PI) * 1.2, 0), 0.0, 1.0, 0.55)
	t.tween_callback(orb.queue_free)

func _drop_loot():
	if _rng.randf() > LOOT_CHANCE:
		return
	var item: ItemData
	if _rng.randf() < 0.3:
		item = HealthPack.new()
		item.heal_amount = LootContainer.HEALTH_PACK_HEAL
	else:
		var aw = LootContainer.ammo_weights()
		var types = aw.keys()
		var total = 0
		for t in types:
			total += aw[t]
		var roll = _rng.randi() % max(total, 1)
		var pick = types[0]
		for t in types:
			roll -= aw[t]
			if roll < 0:
				pick = t
				break
		item = AmmoItem.new(pick, LootContainer.AMMO_PER_PICKUP.get(pick, 30))
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.loot_manager:
		nm.loot_manager.drop_from(self, item)

# ---------------------------------------------------------------- clients: following the server

## The server's state for this weed: [kind, x, y, z, yaw, hp, max_hp, anim]
## The state goes out 20 times a second to every client near the weed, so it is packed small:
## [kind, x, y, z, yaw (all * 100), health, max health, anim] as int32 (40 bytes, the old mixed
## array of strings and doubles was 104)
const ANIMS = ["idle", "walk", "attack", "hit", "death"]

static func kind_of_state(s: PackedInt32Array) -> String:
	var kinds = KINDS.keys()
	return kinds[clampi(s[0], 0, kinds.size() - 1)]

static func position_of_state(s: PackedInt32Array) -> Vector3:
	return Vector3(s[1], s[2], s[3]) * 0.01

func apply_state(s: PackedInt32Array):
	_net_pos = position_of_state(s)
	_net_yaw = s[4] * 0.01
	health.max_health = float(s[6])
	var hp = float(s[5])
	if hp < health.current_health:
		health._apply_damage(health.current_health - hp)
	elif hp > health.current_health:
		health._apply_heal(hp - health.current_health)
	var st: String = ANIMS[clampi(s[7], 0, ANIMS.size() - 1)]
	if st == "attack" and anim_state != "attack":
		var fwd = Vector3(sin(_net_yaw), 0, cos(_net_yaw))
		if cfg().style == "melee":
			AbilityFX.slash(self, fwd, cfg().range, 100.0, cfg().color)
	if st != anim_state:
		_play(st)

func get_state() -> PackedInt32Array:
	var p = global_position * 100.0
	return PackedInt32Array([KINDS.keys().find(kind), roundi(p.x), roundi(p.y), roundi(p.z), roundi(wrapf(rotation.y, -PI, PI) * 100.0),
		int(ceil(health.current_health)), int(health.max_health), maxi(ANIMS.find(anim_state), 0)])

func _follow_network(delta: float):
	var k = 1.0 - exp(-12.0 * delta)
	var before = global_position
	global_position = global_position.lerp(_net_pos, k)
	rotation.y = lerp_angle(rotation.y, _net_yaw, k)
	if not _anim:
		_procedural(delta, before.distance_to(global_position) > 0.01)

## Without clips: a bob and a waddle
func _procedural(delta: float, moving: bool):
	_bob += delta * (9.0 if moving else 2.5)
	_model.position.y = abs(sin(_bob)) * (0.08 if moving else 0.02)
	_model.rotation.z = sin(_bob) * (0.08 if moving else 0.02)
