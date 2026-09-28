## Timed states abilities put on heroes: stun (no moving, shooting or casting), slow, blind (the fog
## of war closes in), stealth (nobody sees you from further than STEALTH_REVEAL) and knockback.
## Server-authoritative like damage: apply() only counts on the server; the state reaches clients
## in the player state (ServerPlayer.get_sync_data "fx" -> from_sync), so the victim's own client
## moves / sees like its server copy. A knockback is a MovementComponent.dash, replayed once on the
## victim's client (numbered). Entity meta "cc_immune" (Unshakable) ignores stun, slow, blind, push.
extends Component
class_name StatusComponent

signal changed

const STEALTH_REVEAL: float = 2.2      # world units: this close a stealthed hero is seen anyway
const CROWD_CONTROL = ["stun", "slow", "blind"]

var effects: Dictionary = {}           # kind -> {left: float, value: float}
var _push: Array = []                  # [vx, vz, seconds, number] - the last knockback, for the sync
var _push_left: float = 0.0            # how long the last knockback stays in the sync
var _push_number: int = 0
var _last_push_applied: int = 0        # client: the last knockback number already replayed
var _visual: Node3D = null

func _init(p_entity = null):
	entity = p_entity

func _is_authority() -> bool:
	if not entity or not entity.is_inside_tree():
		return true
	var mp = entity.get_tree().get_multiplayer()
	return not mp.has_multiplayer_peer() or mp.is_server()

func _immune(kind: String) -> bool:
	return entity and entity.has_meta("cc_immune") and (kind in CROWD_CONTROL or kind == "push")

## Server: put `kind` on for `seconds` (the longer one wins); `value` = slow / blind factor
func apply(kind: String, seconds: float, value: float = 1.0) -> bool:
	if not enabled or seconds <= 0.0 or not _is_authority() or _immune(kind):
		return false
	var health = entity.get_component("HealthComponent") if entity else null
	if health and health.is_dead:
		return false
	var current = effects.get(kind, {"left": 0.0, "value": value})
	effects[kind] = {"left": max(current.left, seconds), "value": value}
	if kind == "stun":
		var movement = entity.get_component("MovementComponent")
		if movement:
			movement.set_move_direction(Vector3.ZERO)
	_refresh_visual()
	changed.emit()
	return true

func clear(kind: String) -> void:
	if effects.erase(kind):
		_refresh_visual()
		changed.emit()

## Server: shove this hero (a dash it can't steer), replayed on the victim's own client
func push(velocity: Vector3, seconds: float) -> bool:
	if not enabled or not _is_authority() or _immune("push"):
		return false
	var movement = entity.get_component("MovementComponent") if entity else null
	if not movement:
		return false
	movement.dash(velocity, seconds)
	_push_number += 1
	_push = [velocity.x, velocity.z, seconds, _push_number]
	_push_left = 0.4  # a few world states carry it (20 per second)
	return true

func has(kind: String) -> bool:
	return effects.has(kind)

func is_stunned() -> bool:
	return effects.has("stun")

func is_stealthed() -> bool:
	return effects.has("stealth")

## Walking speed factor (slow)
func movement_factor() -> float:
	return float(effects.slow.value) if effects.has("slow") else 1.0

## Sight factor (blind)
func sight_factor() -> float:
	return float(effects.blind.value) if effects.has("blind") else 1.0

func update(delta: float):
	if effects.is_empty() and _push_left <= 0.0:
		return
	_push_left = max(_push_left - delta, 0.0)
	var ended := false
	for kind in effects.keys():
		effects[kind].left -= delta
		if effects[kind].left <= 0.0:
			effects.erase(kind)
			ended = true
	if ended:
		_refresh_visual()
		changed.emit()
	_animate_visual(delta)

# ---------------------------------------------------------------- network

func to_sync() -> Dictionary:
	var data := {}
	for kind in effects:
		data[kind] = [snappedf(effects[kind].left, 0.05), effects[kind].value]
	if _push_left > 0.0 and not _push.is_empty():
		data["push"] = _push
	return data

## Client: the server's view of this hero. `local`: our own predicted player (replay knockbacks)
func from_sync(data: Dictionary, local: bool) -> void:
	var before = effects.keys()
	effects.clear()
	for kind in data:
		if kind == "push":
			continue
		var entry: Array = data[kind]
		effects[kind] = {"left": float(entry[0]), "value": float(entry[1]) if entry.size() > 1 else 1.0}
	if local and data.has("push"):
		var p: Array = data.push
		if int(p[3]) > _last_push_applied:
			_last_push_applied = int(p[3])
			var movement = entity.get_component("MovementComponent")
			if movement:
				movement.dash(Vector3(float(p[0]), 0.0, float(p[1])), float(p[2]))
	if local and effects.has("stun"):
		var movement = entity.get_component("MovementComponent")
		if movement:
			movement.set_move_direction(Vector3.ZERO)
	var after = effects.keys()
	before.sort()
	after.sort()
	if before != after:
		_refresh_visual()
		changed.emit()

# ---------------------------------------------------------------- look

## Stars over a stunned head, a dark cloud over a blind one; a stealthed hero turns see-through
func _refresh_visual() -> void:
	if not entity or not entity.is_inside_tree():
		return
	if _visual and is_instance_valid(_visual):
		_visual.queue_free()
	_visual = null
	var model = entity.get_node_or_null("Model")
	if model:
		_set_transparency(model, 0.65 if is_stealthed() else 0.0)
	if not is_stunned() and not effects.has("blind"):
		return
	_visual = Node3D.new()
	_visual.name = "StatusVisual"
	entity.add_child(_visual)
	_visual.position = Vector3(0, 1.55, 0)
	var color = Color(1.0, 0.92, 0.35) if is_stunned() else Color(0.25, 0.22, 0.3)
	for i in 3:
		var star = MeshInstance3D.new()
		var mesh = PrismMesh.new() if is_stunned() else SphereMesh.new()
		if mesh is PrismMesh:
			mesh.size = Vector3(0.14, 0.14, 0.05)
		else:
			mesh.radius = 0.13
			mesh.height = 0.2
		star.mesh = mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = is_stunned()
		mat.emission = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		star.material_override = mat
		var a = TAU * i / 3.0
		star.position = Vector3(cos(a), 0.0, sin(a)) * 0.28
		_visual.add_child(star)

func _animate_visual(delta: float) -> void:
	if _visual and is_instance_valid(_visual):
		_visual.rotation.y += delta * 5.0

func _set_transparency(node: Node, t: float) -> void:
	if node is GeometryInstance3D:
		node.transparency = t
	for child in node.get_children():
		_set_transparency(child, t)
