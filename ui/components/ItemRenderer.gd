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
	elif kind == "item":
		# A pickup (medkit, shield, crystal, ammo) seen from a little above, a bit turned
		var data: ItemData = null
		if int(args[0]) == LootItem.ItemType.AMMO:
			data = AmmoItem.new(int(args[1]), 1)
		var model = LootVisuals.pickup_model(int(args[0]), data)
		if model:
			LootVisuals.fit(model, 1.1)
			var turn = Node3D.new()
			turn.add_child(model)
			turn.rotation = Vector3(deg_to_rad(10), deg_to_rad(-30), 0)
			pivot.add_child(turn)
		camera.look_at_from_position(Vector3(0, 0.9, 3.4), Vector3(0, 0, 0))
	else:
		var weapon = RangedWeapon.create_weapon(args[0])
		var model = LootVisuals.pickup_model(LootItem.ItemType.WEAPON, weapon)
		if model:
			Cosmetics.apply_to_weapon(model, args[1])
			LootVisuals.fit_length(model, 1.2 * LootVisuals.weapon_scale(weapon))  # true to size between guns
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

## A pickup: LootItem.ItemType (HEALTH / SHIELD / ABILITY_BOOST / AMMO) and the ammo type for ammo
func item(item_type: int, ammo_type: int, callback: Callable) -> void:
	_request("item|%d|%d" % [item_type, ammo_type], "item", [item_type, ammo_type], callback)

## The picture of an inventory item (the HUD and the inventory menu): a gun in the finish it
## wears for us, a medkit, a shield, a clip of the right ammo. Perks have none (no callback).
## Pictures are cropped to the model (a gun side-on is a thin strip of the square snapshot), so
## they fill a small slot
func icon_for(it: ItemData, callback: Callable) -> void:
	var crop = func(tex): callback.call(cropped(tex))
	if it is RangedWeapon:
		# Guns share one frame (the longest gun's): cropping each to its outline would make them
		# all the same size again
		weapon(int(it.weapon_type), PlayerProfile.weapon_finish_for(int(it.weapon_type)), func(tex): callback.call(gun_frame(tex)))
	elif it is HealthPack:
		item(LootItem.ItemType.HEALTH, 0, crop)
	elif it is ShieldPack:
		item(LootItem.ItemType.SHIELD, 0, crop)
	elif it is AmmoItem:
		item(LootItem.ItemType.AMMO, int(it.ammo_type), crop)

var _crops: Dictionary = {}  # snapshot -> its cropped copy

## The middle of a gun snapshot that the longest gun fills (5 : 3, room for the chunky blasters)
const GUN_FRAME := Rect2i(44, 104, 296, 176)
func gun_frame(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var key = [tex, "frame"]
	if _crops.has(key):
		return _crops[key]
	var out = ImageTexture.create_from_image(tex.get_image().get_region(GUN_FRAME))
	_crops[key] = out
	return out

## The snapshot cut down to what is drawn on it (plus a little air)
func cropped(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	if _crops.has(tex):
		return _crops[tex]
	var img = tex.get_image()
	var used = img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return tex
	used = used.grow(6).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var out = ImageTexture.create_from_image(img.get_region(used))
	_crops[tex] = out
	return out

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
