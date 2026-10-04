## "Where did that come from": a red arc around your hero (the screen middle in third person)
## towards whoever hit you, bigger for bigger hits, fading out. Fed by HealthComponent.hit_from
## (the server's take_damage on the host, the player state's "hits" on clients).
extends Control
class_name DamageIndicator

const LIFE: float = 1.6
const RADIUS: float = 120.0
const MAX_ARCS: int = 8

var player: Player = null
var _arcs: Array = []   # {pos: Vector3, amount, age}
var _health: HealthComponent = null

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func track(p: Player):
	if _health and _health.hit_from.is_connected(_on_hit_from):
		_health.hit_from.disconnect(_on_hit_from)
	player = p
	_arcs.clear()
	_health = p.get_component("HealthComponent") if p else null
	if _health:
		_health.hit_from.connect(_on_hit_from)

func _on_hit_from(pos: Vector3, amount: float):
	Sfx.own("hurt", linear_to_db(clampf(amount / 25.0, 0.4, 1.4)))
	# The same attacker again: refresh its arc instead of stacking
	for arc in _arcs:
		if Vector2(arc.pos.x, arc.pos.z).distance_to(Vector2(pos.x, pos.z)) < 2.0:
			arc.pos = pos
			arc.amount = max(arc.amount * 0.5, 0.0) + amount
			arc.age = 0.0
			return
	_arcs.append({"pos": pos, "amount": amount, "age": 0.0})
	if _arcs.size() > MAX_ARCS:
		_arcs.pop_front()

func _process(delta: float):
	if _arcs.is_empty():
		return
	for arc in _arcs:
		arc.age += delta
	_arcs = _arcs.filter(func(a): return a.age < LIFE)
	queue_redraw()

func _draw():
	if _arcs.is_empty() or not player or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	var tps = camera is CameraController and camera.third_person
	var center = size / 2.0
	if not tps and not camera.is_position_behind(player.global_position):
		center = camera.unproject_position(player.global_position + Vector3(0, 0.8, 0))
	# Screen "up" is the camera's flat forward: the angle is taken in the ground plane
	var fwd = -camera.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	var right = fwd.cross(Vector3.UP)
	var max_hp = 100.0
	var health = player.get_component("HealthComponent")
	if health:
		max_hp = max(health.max_health, 1.0)

	for arc in _arcs:
		var to = arc.pos - player.global_position
		to.y = 0.0
		if to.length_squared() < 0.01:
			continue
		to = to.normalized()
		var screen_angle = atan2(to.dot(right), to.dot(fwd))  # 0 = straight up the screen
		var fade = 1.0 - arc.age / LIFE
		fade = fade * fade
		var strength = clamp(arc.amount / (max_hp * 0.15), 0.35, 1.0)  # a big hit, a big arc
		var width = deg_to_rad(26.0 + 34.0 * strength)
		var mid = screen_angle - PI / 2.0  # draw_arc's 0 points right
		var r = RADIUS * (1.0 + 0.12 * (1.0 - fade))
		var col = Color(1.0, 0.18, 0.15, 0.85 * fade)
		draw_arc(center, r, mid - width / 2.0, mid + width / 2.0, 24, Color(0.1, 0, 0, 0.45 * fade), 14.0, true)
		draw_arc(center, r, mid - width / 2.0, mid + width / 2.0, 24, col, 8.0 + 6.0 * strength, true)
		# A chevron on the arc pointing out towards the shooter
		var dir2 = Vector2(cos(mid), sin(mid))
		var tip = center + dir2 * (r + 22.0)
		var n = Vector2(-dir2.y, dir2.x) * 10.0
		draw_colored_polygon(PackedVector2Array([tip, center + dir2 * (r + 9.0) + n, center + dir2 * (r + 9.0) - n]), col)
