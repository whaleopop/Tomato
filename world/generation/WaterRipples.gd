## Rings on the water around everyone wading through it, plus splashes from landings.
## Feeds the shared water material (ShaderHelper.create_water_material): at most MAX_RIPPLES,
## each vec4(x, z, age, strength) in world space. Added by MapGenerator; only the newest map's
## instance uploads (the host and the cutscene can have two maps alive for a moment).
extends Node
class_name WaterRipples

const MAX_RIPPLES: int = 16          # matches `ripples[16]` in water.gdshader
const LIFETIME: float = 2.2
const MOVE_INTERVAL: float = 0.14    # a new ring this often while someone moves through water
const IDLE_INTERVAL: float = 1.2     # and now and then while they stand in it
const MIN_MOVE_SPEED: float = 0.6

static var _active: WaterRipples = null

var grid: HexGrid = null
var _ripples: Array = []             # [x, z, age, strength]
var _last_pos: Dictionary = {}       # player instance id -> Vector3
var _cooldown: Dictionary = {}       # player instance id -> seconds until the next ring

func _enter_tree():
	_active = self

func _exit_tree():
	if _active == self:
		_active = null
		_upload([])

## Something landed in (or hit) the water at `pos`
static func splash(pos: Vector3, strength: float = 1.0) -> void:
	if _active and is_instance_valid(_active):
		_active._add(pos, clamp(strength * 1.4, 0.3, 1.6))

func _add(pos: Vector3, strength: float) -> void:
	if _ripples.size() >= MAX_RIPPLES:
		_ripples.pop_front()  # oldest first
	_ripples.append([pos.x, pos.z, 0.0, strength])

func _process(delta: float):
	if _active != self or not grid or not is_instance_valid(grid):
		return
	_emit_for_players(delta)

	var alive: Array = []
	for r in _ripples:
		r[2] += delta
		if r[2] < LIFETIME:
			alive.append(r)
	_ripples = alive
	_upload(_ripples)

func _emit_for_players(delta: float) -> void:
	var seen: Dictionary = {}
	for player in get_tree().get_nodes_in_group("players"):
		if not player is Node3D or not player.is_inside_tree():
			continue
		# Hidden (fog of war / server-side fog) players leave no trace
		if not player.is_visible_in_tree() or player.get_meta("net_hidden", false):
			continue
		var id = player.get_instance_id()
		seen[id] = true
		var pos: Vector3 = player.global_position
		var last: Vector3 = _last_pos.get(id, pos)
		_last_pos[id] = pos
		var tile = grid.get_tile(grid.world_to_hex(pos - grid.global_position))
		if not tile or not tile.is_water() or tile.is_destroyed:
			_cooldown.erase(id)
			continue
		# Feet in the water: not jumping / falling far above it
		if pos.y - (tile.global_position.y + HexTile.HEX_HEIGHT * 0.5) > 0.35:
			continue
		var speed = Vector2(pos.x - last.x, pos.z - last.z).length() / max(delta, 0.001)
		var moving = speed > MIN_MOVE_SPEED
		var left = _cooldown.get(id, 0.0) - delta
		if left <= 0.0:
			# Rings trail a little behind the feet, stronger when running
			_add(pos, clamp(0.45 + speed * 0.08, 0.45, 1.0) if moving else 0.3)
			left = MOVE_INTERVAL if moving else IDLE_INTERVAL
		_cooldown[id] = left
	for id in _last_pos.keys():
		if not seen.has(id):
			_last_pos.erase(id)
			_cooldown.erase(id)

func _upload(list: Array) -> void:
	var material = ShaderHelper.create_water_material() as ShaderMaterial
	if not material:
		return
	var data := PackedVector4Array()
	data.resize(MAX_RIPPLES)
	for i in list.size():
		var r = list[i]
		data[i] = Vector4(r[0], r[1], r[2], r[3])
	material.set_shader_parameter("ripples", data)
	material.set_shader_parameter("ripple_count", list.size())
