## Sound effects. The sounds are audio/sfx/<id>.ogg, cut from FL Studio's factory sample packs by
## tools/audio/make_sfx.py (which also sets their loudness). Three buses under Master, each with a
## volume slider in Settings (GameSettings): "SFX" (the world: guns, blasts, loot, abilities,
## weeds, the zone), "UI" (menus, countdown, results) and "Ambient" (AmbientSound).
## `at(id, pos)` plays in 3D where it happens - the listener is at the hero, turned like the camera
## (CameraController), not up in the sky with it; `ui(id)` plays flat. Nothing plays on a headless
## server. Looks and sounds only: nothing here is synced, every peer plays what it sees happen.
extends RefCounted
class_name Sfx

const DIR = "res://audio/sfx/"
const BUSES = ["SFX", "UI", "Ambient"]

## RangedWeapon.WeaponType -> its shot
const GUNS = ["gun_pistol", "gun_shotgun", "gun_sniper", "gun_rifle", "gun_flame", "gun_smg", "gun_cannon",
	"gun_marksman", "gun_minigun", "gun_double", "gun_jam", "gun_launcher"]

## Per sound, if not the default: range (metres heard), pitch (random +- spread), limit (copies
## at once - the oldest stops), db (extra volume)
const DEFAULT = {"range": 40.0, "pitch": 0.06, "limit": 5, "db": 0.0}
const TUNE = {
	"gun_minigun": {"limit": 6, "pitch": 0.1}, "gun_smg": {"limit": 6, "pitch": 0.1},
	"gun_flame": {"limit": 3}, "gun_sniper": {"range": 70.0}, "gun_cannon": {"range": 60.0},
	"explosion": {"range": 70.0, "limit": 4}, "rumble": {"range": 90.0, "limit": 2, "pitch": 0.0},
	"meteor": {"range": 90.0}, "supply_drop": {"range": 90.0, "limit": 2, "pitch": 0.0},
	"thud": {"limit": 4, "range": 30.0}, "hit": {"limit": 3, "pitch": 0.12}, "wall_hit": {"limit": 3, "range": 25.0},
	"weed_spit": {"range": 30.0}, "weed_die": {"range": 30.0}, "chest_open": {"range": 30.0},
	"ui_hover": {"limit": 2, "pitch": 0.0}, "ui_click": {"limit": 3, "pitch": 0.02},
	"victory": {"limit": 1, "pitch": 0.0}, "defeat": {"limit": 1, "pitch": 0.0}, "night": {"limit": 1, "pitch": 0.0},
	"zone_warn": {"limit": 1, "pitch": 0.0},
}

static var _streams: Dictionary = {}   # id -> AudioStream (null: no such file)
static var _playing: Dictionary = {}   # id -> [players]

static func enabled() -> bool:
	return DisplayServer.get_name() != "headless"

static func tune(id: String, key: String):
	return TUNE.get(id, {}).get(key, DEFAULT[key])

static func stream(id: String) -> AudioStream:
	if not _streams.has(id):
		var path = DIR + id + ".ogg"
		_streams[id] = load(path) if ResourceLoader.exists(path) else null
	return _streams[id]

## The buses (once; GameSettings.apply sets their volumes)
static func ensure_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i = AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")

static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

## A sound out in the world at `pos`
static func at(id: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled() or stream(id) == null:
		return
	var tree = _tree()
	var parent = tree.current_scene if tree and tree.current_scene is Node3D else (tree.root if tree else null)
	if parent == null:
		return
	var p = AudioStreamPlayer3D.new()
	p.stream = stream(id)
	p.bus = "SFX"
	p.max_distance = float(tune(id, "range"))
	p.unit_size = p.max_distance * 0.22
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.panning_strength = 0.6
	p.volume_db = volume_db + float(tune(id, "db"))
	p.pitch_scale = pitch * (1.0 + randf_range(-1.0, 1.0) * float(tune(id, "pitch")))
	parent.add_child(p)
	p.global_position = pos
	_start(id, p)

## A sound with no place: menus, your own hero's reload / hurt, the result screen
static func ui(id: String, volume_db: float = 0.0, pitch: float = 1.0, bus: String = "UI") -> void:
	if not enabled() or stream(id) == null:
		return
	var tree = _tree()
	if tree == null:
		return
	var p = AudioStreamPlayer.new()
	p.stream = stream(id)
	p.bus = bus
	p.volume_db = volume_db + float(tune(id, "db"))
	p.pitch_scale = pitch * (1.0 + randf_range(-1.0, 1.0) * float(tune(id, "pitch")))
	tree.root.add_child(p)
	_start(id, p)

## Our own hero's sounds: flat, but on the world's bus (the effects slider)
static func own(id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	ui(id, volume_db, pitch, "SFX")

## A gun's shot (RangedWeapon.WeaponType)
static func shot(weapon_type: int, pos: Vector3) -> void:
	if weapon_type >= 0 and weapon_type < GUNS.size():
		at(GUNS[weapon_type], pos)

static func _start(id: String, p: Node) -> void:
	var list: Array = _playing.get_or_add(id, [])
	list = list.filter(func(o): return is_instance_valid(o))
	while list.size() >= int(tune(id, "limit")):
		var oldest = list.pop_front()
		oldest.queue_free()
	list.append(p)
	_playing[id] = list
	p.finished.connect(p.queue_free)
	p.play()
