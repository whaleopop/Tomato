## Pictures for the shop / starter cards. Two ways:
##   - snapshots: a hero (with a skin and a hat) or a gun (with a finish) photographed once on a
##     transparent background and cached - every card shows one;
##   - live: a real 3D model in its own viewport for the card under the mouse (and the shop's big
##     card), turned as the card tilts (live_begin / live_turn / live_end). Only a few exist at
##     a time, so a screen full of cards stays cheap.
extends Node
class_name ItemRenderer

const SIZE: int = 384
const HERO_YAW: float = -0.44   # radians: the heroes look a little to the side

static var _instance: ItemRenderer = null

var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _cache: Dictionary = {}     # key -> Texture2D
var _queue: Array = []          # [key, kind, args, callbacks]
var _busy: bool = false
var _live: Dictionary = {}      # owner -> {viewport, pivot, kind}

## The shared renderer (lives under the scene tree root)
static func get_instance(tree: SceneTree) -> ItemRenderer:
	if _instance and is_instance_valid(_instance):
		return _instance
	_instance = ItemRenderer.new()
	_instance.name = "ItemRenderer"
	tree.root.add_child.call_deferred(_instance)
	return _instance

func _ready():
	var parts = _make_viewport(SubViewport.UPDATE_DISABLED)
	_viewport = parts[0]
	_stage = parts[1]
	_camera = parts[2]

## A transparent viewport with its own world, lights, a stage and a camera
func _make_viewport(mode: int) -> Array:
	var viewport = SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = mode
	add_child(viewport)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	viewport.add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.3
	viewport.add_child(sun)
	var rim = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 200, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.8, 0.85, 1.0)
	viewport.add_child(rim)
	var stage = Node3D.new()
	viewport.add_child(stage)
	var camera = Camera3D.new()
	camera.fov = 30.0
	viewport.add_child(camera)
	camera.current = true
	return [viewport, stage, camera]

## Build the model on `stage` inside a pivot (turned by live cards) and aim `camera` at it
func _place(stage: Node3D, camera: Camera3D, kind: String, args: Array) -> Node3D:
	for child in stage.get_children():
		child.free()
	var pivot = Node3D.new()
	stage.add_child(pivot)
	if kind == "hero":
		var data = CharacterRegistry.get_by_name(args[0])
		if data and ResourceLoader.exists(data.model_path):
			var model = load(data.model_path).instantiate()
			ModelUtils.apply_lowpoly_look(model)
			pivot.add_child(model)
			ModelUtils.normalize_to_height(model, 1.2)
			Cosmetics.apply_to_character(model, args[1], args[2])
			var anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if anim and anim.has_animation("idle"):
				anim.play("idle")
		pivot.rotation.y = HERO_YAW
		camera.look_at_from_position(Vector3(0, 0.95, 4.2), Vector3(0, 0.7, 0))  # works before the viewport is in the tree
	else:
		var weapon = RangedWeapon.create_weapon(args[0])
		var model = LootVisuals.pickup_model(LootItem.ItemType.WEAPON, weapon)
		if model:
			Cosmetics.apply_to_weapon(model, args[1])
			LootVisuals.fit(model, 1.25)
			var turn = Node3D.new()
			turn.add_child(model)
			turn.rotation = Vector3(deg_to_rad(8), deg_to_rad(-70), 0)  # side-on, barrel to the right
			pivot.add_child(turn)
		camera.look_at_from_position(Vector3(0, 0.15, 3.6), Vector3(0, 0, 0))
	return pivot

# ---------------------------------------------------------------- snapshots

## A hero wearing `skin` / `hat`; `callback(texture)` gets the picture (right away if cached)
func hero(hero_name: String, skin: String, hat: String, callback: Callable) -> void:
	_request("hero|%s|%s|%s" % [hero_name, skin, hat], "hero", [hero_name, skin, hat], callback)

## A gun with a finish
func weapon(weapon_type: int, finish: String, callback: Callable) -> void:
	_request("gun|%d|%s" % [weapon_type, finish], "gun", [weapon_type, finish], callback)

func _request(key: String, kind: String, args: Array, callback: Callable) -> void:
	if _cache.has(key):
		callback.call(_cache[key])
		return
	for q in _queue:
		if q[0] == key:
			q[3].append(callback)
			return
	_queue.append([key, kind, args, [callback]])
	if not _busy:
		_busy = true  # right away: every request before the deferred start used to start its own loop
		_run.call_deferred()

func _run() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	while not _queue.is_empty():
		var job = _queue.pop_front()
		_place(_stage, _camera, job[1], job[2])
		# The picture of this model is only ready a couple of frames later (bone attachments follow
		# their bone, the viewport draws after the scene): taking it earlier gave the previous model
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var tex = ImageTexture.create_from_image(_viewport.get_texture().get_image())
		_cache[job[0]] = tex
		for cb in job[3]:
			if cb.is_valid():
				cb.call(tex)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_busy = false

# ---------------------------------------------------------------- live models

## A live 3D model for `owner` (a card): its viewport texture to show while it lasts
func live_begin(owner: Object, kind: String, args: Array) -> Texture2D:
	live_end(owner)
	var parts = _make_viewport(SubViewport.UPDATE_ALWAYS)
	var pivot = _place(parts[1], parts[2], kind, args)
	_live[owner] = {"viewport": parts[0], "pivot": pivot, "kind": kind}
	return parts[0].get_texture()

## Turn the live model: yaw / pitch in radians (the card's tilt)
func live_turn(owner: Object, yaw: float, pitch: float) -> void:
	if not _live.has(owner):
		return
	var entry = _live[owner]
	var pivot: Node3D = entry.pivot
	if is_instance_valid(pivot):
		pivot.rotation.y = (HERO_YAW if entry.kind == "hero" else 0.0) + yaw
		pivot.rotation.x = pitch

func live_end(owner: Object) -> void:
	if not _live.has(owner):
		return
	var viewport = _live[owner].viewport
	_live.erase(owner)
	if is_instance_valid(viewport):
		viewport.queue_free()
