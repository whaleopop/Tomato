## Spawn cutscene: a meteor carries the heroes over the island, they leap off and land
## at their spawn points. The camera stays close to YOUR hero:
##   RIDE    - chase cam next to the meteor, heroes standing on top
##   FLIGHT  - follows your hero through the air
##   LANDING - impact + low-angle close-up + "<NAME> LANDED!" banner
##   OUTRO   - glides to the gameplay camera angle, then the match starts seamlessly
extends Node3D
class_name SpawnCutsceneController

signal cutscene_finished

enum Phase { RIDE, FLIGHT, LANDING, OUTRO, FINISHED }

const METEOR_SPEED: float = 13.0         # horizontal units per second
const PASS_TIME: float = 2.6             # meteor is above your spawn at this time
const FLIGHT_TIME: float = 1.7
const CLOSEUP_TIME: float = 1.9
const OUTRO_TIME: float = 1.3
const MAX_DURATION: float = 14.0
const GAME_CAMERA_OFFSET := Vector3(0, 8.1, 2.6)  # where CameraController sits at its fixed (closest) zoom

var current_phase: Phase = Phase.RIDE
var elapsed_time: float = 0.0
var phase_time: float = 0.0
var cutscene_started: bool = false

# Spawn data
var spawn_positions: Dictionary = {}  # player_id -> Vector3
var player_characters: Dictionary = {}  # player_id -> String
var map_seed: int = 0
var local_player_id: int = 1

# Nodes
var meteor: Node3D = null
var cutscene_camera: CutsceneCamera = null
var world_container: Node3D = null
var heroes: Array[Dictionary] = []   # {id, node, spawn, detach_time, detached, landed, ...}
var local_hero: Dictionary = {}

# Meteor path: straight line that passes high over your spawn point at PASS_TIME
var meteor_dir: Vector3 = Vector3(1, 0, -0.55).normalized()
var meteor_origin: Vector3 = Vector3.ZERO
const METEOR_ALTITUDE: float = 20.0
const METEOR_SINK: float = 1.4           # altitude lost per second

# UI
var title_holder: Control = null
var banner_holder: Control = null

func _ready():
	add_to_group("spawn_cutscene")
	world_container = get_node_or_null("WorldContainer")
	meteor = get_node_or_null("MeteorVisual")
	cutscene_camera = get_node_or_null("CutsceneCamera")

	_setup_environment()
	_create_overlay_ui()
	_load_cutscene_data()
	await _generate_map()
	if not is_inside_tree():
		return
	_setup_heroes()
	_start_cutscene()

## Same sky / sun / abyss as the match, instead of the flat grey placeholder
func _setup_environment():
	for n in ["WorldEnvironment", "DirectionalLight"]:
		var old = get_node_or_null(n)
		if old:
			old.queue_free()
	var env = GameEnvironment.new()
	env.name = "GameEnvironment"
	add_child(env)

func _load_cutscene_data():
	var game_manager = get_node_or_null("/root/GameManager")
	var network_manager = get_node_or_null("/root/NetworkManager")
	if game_manager:
		map_seed = game_manager.map_seed

	local_player_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1

	if network_manager and network_manager.is_server():
		var game_server = network_manager.game_server
		var lobby = game_server.lobby_manager
		if game_server.server_world and game_server.server_world.hex_grid:
			for player_id in lobby.players_spawn.keys():
				spawn_positions[player_id] = lobby.get_spawn_position(player_id, game_server.server_world.hex_grid)
				player_characters[player_id] = lobby.get_player_character(player_id)
	elif game_manager:
		spawn_positions = game_manager.cutscene_spawn_positions.duplicate()
		player_characters = game_manager.cutscene_player_characters.duplicate()

	# Missing / unselected spawns fall back to the map center
	for player_id in spawn_positions.keys():
		if spawn_positions[player_id] == Vector3.ZERO:
			spawn_positions[player_id] = Vector3(0, 1.4, 0)
	if not spawn_positions.has(local_player_id):
		spawn_positions[local_player_id] = Vector3(0, 1.4, 0)
	if not player_characters.has(local_player_id) or player_characters[local_player_id] == "":
		var char_name = "Tomato"
		if game_manager and game_manager.selected_character:
			char_name = game_manager.selected_character.character_name
		player_characters[local_player_id] = char_name
	print("[SpawnCutscene] Loaded data for %d players" % spawn_positions.size())

func _generate_map():
	# Host: the server map already sits at the world origin; a second copy would z-fight
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_server() and network_manager.game_server.server_world.is_map_ready:
		return
	var map_generator = MapGenerator.new()
	world_container.add_child(map_generator)
	var seed_to_use = map_seed if map_seed != 0 else -1
	var grid = await map_generator.generate_map(MapGenerator.MATCH_MAP_RADIUS, seed_to_use)
	if map_seed != 0 and grid and is_inside_tree():
		# The same containers, walls and bushes the match will have (all seeded)
		var loot = LootSpawner.new()
		world_container.add_child(loot)
		loot.setup(grid, map_seed)
		var cover = CoverSpawner.new()
		world_container.add_child(cover)
		cover.setup(grid, map_seed, CoverSpawner.container_tiles(grid, loot))

# ---------------------------------------------------------------- heroes

func meteor_position_at(t: float) -> Vector3:
	var p = meteor_origin + meteor_dir * METEOR_SPEED * t
	p.y = spawn_positions[local_player_id].y + METEOR_ALTITUDE - METEOR_SINK * t
	return p

func _meteor_top() -> float:
	return meteor.meteor_radius * 0.92 if meteor and "meteor_radius" in meteor else 2.8

func _setup_heroes():
	var local_spawn: Vector3 = spawn_positions[local_player_id]
	meteor_origin = local_spawn - meteor_dir * METEOR_SPEED * PASS_TIME
	var container = get_node_or_null("HeroProxies")
	var side = Vector3.UP.cross(meteor_dir).normalized()

	# Local hero stands at the front of the meteor, the others behind in a fan
	var ids = spawn_positions.keys()
	ids.erase(local_player_id)
	ids.push_front(local_player_id)
	for i in ids.size():
		var player_id = ids[i]
		var spawn: Vector3 = spawn_positions[player_id]
		var slot = Vector3.ZERO
		if i > 0:
			var row = int((i - 1) / 2) + 1
			var side_sign = -1.0 if i % 2 == 1 else 1.0
			slot = -meteor_dir * 0.9 * row + side * side_sign * 1.0 * row
		var along = (spawn - local_spawn).dot(meteor_dir) / METEOR_SPEED
		var detach = PASS_TIME - 0.55 if player_id == local_player_id else clamp(PASS_TIME + along - 0.55, 0.9, 7.5)
		var hero = {
			"id": player_id,
			"node": _create_hero(player_characters.get(player_id, "Tomato")),
			"spawn": spawn,
			"slot": slot,
			"detach_time": detach,
			"detached": false,
			"landed": false,
			"yaw": atan2(meteor_dir.x, meteor_dir.z),
			"color": _character_color(player_characters.get(player_id, "")),
		}
		container.add_child(hero.node)
		heroes.append(hero)
		if player_id == local_player_id:
			local_hero = hero
		_play(hero, "idle")

func _create_hero(char_name: String) -> Node3D:
	var proxy = Node3D.new()
	proxy.name = "Hero_" + char_name
	var data = CharacterRegistry.get_by_name(char_name)
	var scene = load(data.model_path) if data and ResourceLoader.exists(data.model_path) else null
	if scene:
		var model = scene.instantiate()
		ModelUtils.apply_lowpoly_look(model)
		proxy.add_child(model)
		ModelUtils.normalize_to_height(model, 1.25)
	else:
		var mesh = MeshInstance3D.new()
		mesh.mesh = CapsuleMesh.new()
		var mat = StandardMaterial3D.new()
		mat.albedo_color = data.color if data else Color(0.8, 0.3, 0.3)
		mesh.material_override = mat
		mesh.position.y = 1.0
		proxy.add_child(mesh)

	var trail = GPUParticles3D.new()
	trail.name = "Trail"
	trail.amount = 60
	trail.lifetime = 0.5
	trail.local_coords = false
	trail.emitting = false
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.gravity = Vector3(0, 1.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var ramp = Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 0.9))
	ramp.set_color(1, Color(1.0, 0.35, 0.1, 0.0))
	var ramp_tex = GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	trail.process_material = pm
	var quad = QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	quad.material = LandingImpact.soft_particle_material(true)
	trail.draw_pass_1 = quad
	trail.position.y = 0.6
	proxy.add_child(trail)
	return proxy

func _character_color(char_name: String) -> Color:
	var data = CharacterRegistry.get_by_name(char_name)
	return data.color if data else Color(1.0, 0.8, 0.5)

## Rigged heroes play their skeletal clips; static models get the same beats procedurally
func _play(hero: Dictionary, clip: String, blend: float = 0.15):
	var players = hero.node.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var ap: AnimationPlayer = players[0]
	if not ap.has_animation(clip):
		return
	if clip == "idle":
		ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	ap.play(clip, blend)

## Lobby spawn points float 1 unit above the tile (for physics); land on the real surface
func _ground_at(pos: Vector3) -> Vector3:
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(pos + Vector3(0, 6, 0), pos - Vector3(0, 30, 0))
	var hit = space.intersect_ray(query)
	return hit.position if hit else pos

func _detach(hero: Dictionary):
	hero.spawn = _ground_at(hero.spawn)
	hero.detached = true
	hero.detach_at = elapsed_time
	hero.from = hero.node.global_position
	var mid = (hero.from + hero.spawn) / 2.0
	mid.y = max(hero.from.y, hero.spawn.y) + 4.0
	hero.mid = mid
	var flat = Vector3(hero.spawn.x - hero.from.x, 0, hero.spawn.z - hero.from.z)
	hero.yaw = atan2(flat.x, flat.z) if flat.length() > 0.01 else hero.node.rotation.y
	hero.node.get_node("Trail").emitting = true
	_play(hero, "jump")
	# Little burst where they push off
	LandingImpact.create_at(world_container, hero.from, Color(1.0, 0.7, 0.3), 0.45)

func _update_flight(hero: Dictionary):
	var t = clamp((elapsed_time - hero.detach_at) / FLIGHT_TIME, 0.0, 1.0)
	var e = t * t * (3.0 - 2.0 * t)  # smoothstep: hang at the top, speed into the ground
	var a: Vector3 = hero.from
	var b: Vector3 = hero.mid
	var c: Vector3 = hero.spawn
	var pos = a.lerp(b, e).lerp(b.lerp(c, e), e)
	hero.node.global_position = pos
	# Face the landing spot and do one front flip mid-air. Always set the whole rotation:
	# reading back Euler angles past 90 degrees of pitch flips yaw/roll and leaves the hero upside down
	var flip = clamp((t - 0.2) / 0.6, 0.0, 1.0)
	hero.node.rotation = Vector3(TAU * (flip * flip * (3.0 - 2.0 * flip)), hero.yaw, 0.0)
	if t >= 1.0:
		_land(hero)

func _land(hero: Dictionary):
	hero.landed = true
	hero.node.global_position = hero.spawn
	hero.node.rotation = Vector3(0.0, hero.yaw, 0.0)
	hero.node.get_node("Trail").emitting = false
	LandingImpact.create_at(world_container, hero.spawn, hero.color.lerp(Color.WHITE, 0.4), 1.0)
	HexTile.shake_around(self, hero.spawn, 1.2 if hero.id == local_player_id else 0.9, 3.2)
	# Squash & stretch on impact
	hero.node.scale = Vector3(1.35, 0.55, 1.35)
	var tween = create_tween()
	tween.tween_property(hero.node, "scale", Vector3(0.9, 1.15, 0.9), 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(hero.node, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_play(hero, "land", 0.05)
	get_tree().create_timer(0.35).timeout.connect(func(): _play(hero, "idle"))

	var dist = cutscene_camera.global_position.distance_to(hero.spawn) if cutscene_camera else 99.0
	if cutscene_camera:
		cutscene_camera.add_shake(1.0 if hero.id == local_player_id else clamp(1.0 - dist / 30.0, 0.0, 0.5))

# ---------------------------------------------------------------- timeline

func _start_cutscene():
	cutscene_started = true
	current_phase = Phase.RIDE
	elapsed_time = 0.0
	if meteor:
		meteor.global_position = meteor_position_at(0.0)
		meteor.visible = true
	_update_riders()
	if cutscene_camera:
		cutscene_camera.set_mode(CutsceneCamera.CameraMode.SCRIPTED)
		cutscene_camera.position_smooth = 4.0
		cutscene_camera.look_smooth = 6.0
		var pose = _ride_camera()
		cutscene_camera.snap_to(pose[0], pose[1])

func _process(delta: float):
	if not cutscene_started or current_phase == Phase.FINISHED:
		return
	elapsed_time += delta
	phase_time += delta

	if meteor and meteor.visible:
		var before = meteor.global_position
		meteor.global_position = meteor_position_at(elapsed_time)
		if meteor.has_method("update_trail_direction"):
			meteor.update_trail_direction((meteor.global_position - before) / delta)
		if elapsed_time > 9.0:
			meteor.visible = false

	for hero in heroes:
		if not hero.detached and elapsed_time >= hero.detach_time:
			_detach(hero)
		elif hero.detached and not hero.landed:
			_update_flight(hero)
	_update_riders()
	_update_ui()

	match current_phase:
		Phase.RIDE:
			_set_camera(_ride_camera())
			if local_hero.detached:
				_enter(Phase.FLIGHT)
				cutscene_camera.position_smooth = 12.0  # the hero falls fast; a lazy camera drifts far behind
				cutscene_camera.look_smooth = 14.0
		Phase.FLIGHT:
			_set_camera(_flight_camera())
			if local_hero.landed:
				_enter(Phase.LANDING)
				_turn_to_camera(local_hero)
				_show_banner()
				var pose = _closeup_camera(0.0)
				cutscene_camera.snap_to(pose[0], pose[1])  # hard cut to the hero shot
				cutscene_camera.position_smooth = 4.0
				cutscene_camera.look_smooth = 6.0
		Phase.LANDING:
			_set_camera(_closeup_camera(phase_time / CLOSEUP_TIME))
			if phase_time >= CLOSEUP_TIME:
				_enter(Phase.OUTRO)
				cutscene_camera.position_smooth = 2.6
				cutscene_camera.look_smooth = 3.5
		Phase.OUTRO:
			var spawn: Vector3 = local_hero.spawn
			_set_camera([spawn + GAME_CAMERA_OFFSET, spawn + Vector3(0, 1, 0)])
			if phase_time >= OUTRO_TIME:
				_finish_cutscene()

	if elapsed_time > MAX_DURATION:
		_finish_cutscene()

func _enter(phase: Phase):
	current_phase = phase
	phase_time = 0.0

## Heroes still on the meteor stand on its top
func _update_riders():
	if not meteor:
		return
	var top = meteor.global_position + Vector3(0, _meteor_top(), 0)
	var yaw = atan2(meteor_dir.x, meteor_dir.z)
	for hero in heroes:
		if not hero.detached:
			var bob = sin(elapsed_time * 6.0 + hero.slot.x) * 0.05
			hero.node.global_position = top + hero.slot + Vector3(0, bob, 0)
			hero.node.rotation = Vector3(0, yaw, 0)

func _set_camera(pose: Array):
	if not cutscene_camera:
		return
	var cam_pos: Vector3 = pose[0]
	# Never dip into the terrain (neighbouring tiles can be a step higher)
	if current_phase != Phase.RIDE:
		cam_pos.y = max(cam_pos.y, _ground_at(cam_pos).y + 0.8)
	cutscene_camera.desired_position = cam_pos
	cutscene_camera.look_target = pose[1]

## Beside and slightly ahead of the meteor, looking at the heroes on top
func _ride_camera() -> Array:
	var m = meteor_position_at(elapsed_time)
	var side = Vector3.UP.cross(meteor_dir).normalized()
	var focus = m + Vector3(0, _meteor_top() + 0.8, 0)
	return [focus + side * 4.6 + meteor_dir * 3.4 + Vector3(0, 1.1, 0), focus]

## Behind your hero while they fly towards the spawn
func _flight_camera() -> Array:
	var pos: Vector3 = local_hero.node.global_position
	var back = -Vector3(sin(local_hero.yaw), 0, cos(local_hero.yaw))
	var side = Vector3.UP.cross(back)
	# Over the shoulder, a bit to the side so the flip reads; aim just past the hero towards the landing spot
	var look = pos + (local_hero.spawn - pos).limit_length(1.8) + Vector3(0, 0.6, 0)
	return [pos + back * 3.6 + side * 1.2 + Vector3(0, 1.4, 0), look]

## Low-angle hero shot in front of your hero, slowly dollying in
func _closeup_camera(t: float) -> Array:
	var feet: Vector3 = local_hero.spawn
	var dist = lerp(2.9, 2.2, clamp(t, 0.0, 1.0))
	var cam := Vector3.ZERO
	# Walk around the hero until no wall stands between camera and face (hero turns to match)
	for turn in [0.0, 1.0, -1.0, 2.0, -2.0, 3.0]:
		var yaw: float = local_hero.yaw + turn * PI / 3.0
		var facing = Vector3(sin(yaw), 0, cos(yaw))
		var side = Vector3.UP.cross(facing).normalized()
		# Camera slightly below the face looking up: the classic "hero landing" angle
		cam = feet + facing * dist + side * 0.7 + Vector3(0, 0.7, 0)
		cam.y = max(cam.y, _ground_at(cam).y + 0.8)
		if not CoverSpawner.line_blocked(get_world_3d(), feet + Vector3(0, 0.7, 0), cam):
			if turn != 0.0 and t <= 0.0:
				local_hero.yaw = yaw
				local_hero.node.rotation = Vector3(0.0, yaw, 0.0)
			break
	return [cam, feet + Vector3(0, 0.68, 0)]

## Face back along the flight path, where the camera is
func _turn_to_camera(hero: Dictionary):
	var from_dir: Vector3 = hero.from - hero.spawn
	hero.yaw = atan2(from_dir.x, from_dir.z)
	hero.node.rotation = Vector3(0.0, hero.yaw, 0.0)

# ---------------------------------------------------------------- UI

func _create_overlay_ui():
	var ui = get_node_or_null("UI")
	if not ui:
		return
	title_holder = CenterContainer.new()
	title_holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_holder.grow_horizontal = Control.GROW_DIRECTION_BOTH  # zero-size container: grow both ways to stay centered
	title_holder.offset_top = 26
	title_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(title_holder)
	var col = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_holder.add_child(col)
	UITheme.create_pill("Drop-in", UITheme.ACCENT_SECONDARY, col).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var title = UITheme.create_hero_title("INCOMING!", col)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)

	var bottom = CenterContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.offset_top = -58
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bottom)
	var hint = PanelContainer.new()
	hint.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.14), 99, 16, 6))
	bottom.add_child(hint)
	UITheme.create_label("SPACE - skip", hint, UITheme.FONT_SMALL)

func _update_ui():
	if title_holder and elapsed_time > 2.0 and title_holder.modulate.a > 0.0:
		title_holder.modulate.a = max(0.0, 1.0 - (elapsed_time - 2.0) / 0.5)

func _show_banner():
	var ui = get_node_or_null("UI")
	if not ui or banner_holder:
		return
	var char_name: String = player_characters.get(local_player_id, "Hero")
	var color = _character_color(char_name)
	banner_holder = CenterContainer.new()
	banner_holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_holder.offset_top = 34
	banner_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(banner_holder)
	var card = PanelContainer.new()
	var box = UITheme.glass_box(Color(0.04, 0.05, 0.1, 0.78), Color(color, 0.8), 22, 28, 12)
	box.shadow_color = Color(color, 0.45)
	box.shadow_size = 18
	card.add_theme_stylebox_override("panel", box)
	banner_holder.add_child(card)
	var col = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(col)
	var name_label = UITheme.create_hero_title(tr(char_name).to_upper(), col)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 40)
	name_label.add_theme_color_override("font_color", color.lightened(0.35))
	name_label.add_theme_color_override("font_shadow_color", Color(color, 0.5))
	var sub = UITheme.create_caption("has landed - last one standing wins", col)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Punchy entrance
	card.scale = Vector2(1.4, 1.4)
	card.modulate.a = 0.0
	card.resized.connect(func(): card.pivot_offset = card.size / 2.0)
	var tween = create_tween().set_parallel()
	tween.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate:a", 1.0, 0.2)

# ---------------------------------------------------------------- end

func _unhandled_input(event: InputEvent):
	if current_phase == Phase.FINISHED:
		return
	if event.is_action_pressed("jump") or event.is_action_pressed("ui_accept"):
		_finish_cutscene()

func _finish_cutscene():
	if current_phase == Phase.FINISHED:
		return
	current_phase = Phase.FINISHED
	cutscene_started = false
	cutscene_finished.emit()
	var scene_transition = get_node_or_null("/root/SceneTransition")
	if scene_transition:
		scene_transition.fade_to_scene("res://scenes/GameScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/GameScene.tscn")

## Kept for NetworkCutscene (time sync from the server)
func sync_time(server_time: float, _server_phase: int):
	if abs(elapsed_time - server_time) > 0.2:
		elapsed_time = server_time
