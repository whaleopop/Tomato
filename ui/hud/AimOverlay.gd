## Aim helpers drawn under the crosshair (screen space, projected from the ground at the hero's feet):
## - a ring under your hero, and an arrow at the screen edge when the view ran ahead so far
##   (long guns, CameraController._look_ahead_reach) that the hero is off screen;
## - the gun's reach: the aim line up to its range, a faint range circle, the cone of spread guns
##   and flamethrowers, the blast circle of the grenade launcher;
## - while an ability key is held (PlayerInputHandler.aiming_ability): its area from
##   ActiveAbility.aim_preview() - the cast range, the spot / cone / dash line / area around you.
extends Control
class_name AimOverlay

var player: Player = null

const OUT_OF_RANGE = Color(1.0, 0.45, 0.4)
const EDGE_MARGIN: float = 46.0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta):
	queue_redraw()

func _handler() -> PlayerInputHandler:
	return player.get_node_or_null("InputHandler") as PlayerInputHandler if player else null

func _hero_color() -> Color:
	if player and player.character_data:
		return player.character_data.color.lightened(0.25)
	return UITheme.ACCENT_PRIMARY

## Is the aim point further than the gun reaches? (the crosshair turns red)
static func out_of_range(p: Player) -> bool:
	if not p or not is_instance_valid(p):
		return false
	var combat = p.get_component("CombatComponent")
	var handler = p.get_node_or_null("InputHandler") as PlayerInputHandler
	if not combat or not combat.equipped_ranged_weapon or not handler or handler.current_aim_position == Vector3.ZERO:
		return false
	var off = handler.current_aim_position - p.global_position
	off.y = 0.0
	return off.length() > combat.equipped_ranged_weapon.range

func _draw():
	if not player or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	var health = player.get_component("HealthComponent")
	if health and health.is_dead:
		return
	var tps = camera is CameraController and camera.third_person
	var feet = player.global_position + Vector3(0, 0.08, 0)
	var handler = _handler()
	var aim: Vector3 = handler.current_aim_position if handler else Vector3.ZERO
	var dir = aim - feet
	dir.y = 0.0
	var aim_dist = dir.length()
	dir = dir.normalized() if aim_dist > 0.01 else player.global_transform.basis.z

	var hero_col = _hero_color()
	if not tps:
		_ground_circle(camera, feet, 0.8, Color(hero_col, 0.0), Color(hero_col, 0.7), 2.5)

	var ability_shown = false
	if handler and handler.aiming_ability >= 0:
		ability_shown = _draw_ability(camera, handler.aiming_ability, feet, dir, aim_dist, hero_col)
	if not ability_shown:
		_draw_weapon(camera, feet, dir, aim_dist, tps)

	if not tps:
		_draw_hero_locator(camera, player.global_position + Vector3(0, 0.9, 0), hero_col)

# ---------------------------------------------------------------- gun

func _draw_weapon(camera: Camera3D, feet: Vector3, dir: Vector3, aim_dist: float, tps: bool):
	var combat = player.get_component("CombatComponent")
	var weapon: RangedWeapon = combat.equipped_ranged_weapon if combat else null
	if not weapon:
		return
	var reach = weapon.range
	var line_col = Color(1, 1, 1, 0.4)
	match weapon.fire_mode:
		"spread", "flame":
			var angle = weapon.spread_angle if weapon.spread_angle > 0.0 else 30.0
			angle = min(angle * MapEvents.spread_factor, 60.0)
			_ground_sector(camera, feet, dir, reach, angle, Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.35))
		"lob":
			var land = feet + dir * min(aim_dist, reach)
			_ground_circle(camera, land, max(weapon.blast_radius, 1.0), Color(1.0, 0.55, 0.3, 0.14), Color(1.0, 0.6, 0.35, 0.8), 2.0)
			_ground_line(camera, feet, land, line_col, 2.0, true)
		_:
			# The aim line to the cursor, white while it reaches, red past the gun's range
			if not tps:
				var near = min(aim_dist, reach)
				_ground_line(camera, feet + dir * 0.9, feet + dir * max(near, 0.9), line_col, 2.0, true)
				if aim_dist > reach:
					_ground_line(camera, feet + dir * reach, feet + dir * aim_dist, Color(OUT_OF_RANGE, 0.35), 2.0, true)
					var end = feet + dir * reach
					var side = dir.cross(Vector3.UP) * 0.5
					_ground_line(camera, end - side, end + side, Color(OUT_OF_RANGE, 0.9), 3.0, false)
	# The range itself, faint (in third person it would fill the horizon)
	if not tps:
		_ground_circle(camera, feet, reach, Color(0, 0, 0, 0), Color(1, 1, 1, 0.12), 1.5, true)

# ---------------------------------------------------------------- abilities

func _draw_ability(camera: Camera3D, index: int, feet: Vector3, dir: Vector3, aim_dist: float, hero_col: Color) -> bool:
	var abilities = player.get_component("AbilityComponent")
	if not abilities or index >= abilities.active_abilities.size():
		return false
	var ability: ActiveAbility = abilities.active_abilities[index]
	var p: Dictionary = ability.aim_preview()
	var ready = abilities.get_ability_cooldown(ability) <= 0.0
	var col = hero_col if ready else Color(0.6, 0.6, 0.65)
	var fill = Color(col, 0.22)
	var edge = Color(col, 0.9)
	var reach = float(p.get("range", 0.0))
	match String(p.get("shape", "self")):
		"circle":
			_ground_circle(camera, feet, reach, Color(0, 0, 0, 0), Color(col, 0.45), 2.0, true)
			var spot = feet + dir * min(aim_dist, reach)
			_ground_circle(camera, spot, float(p.get("radius", 1.0)), fill, edge, 2.5)
			_ground_line(camera, feet, spot, Color(col, 0.5), 2.0, true)
		"cone":
			_ground_sector(camera, feet, dir, reach, float(p.get("angle", 60.0)), fill, edge)
		"line":
			var w = float(p.get("width", 1.0)) * 0.5
			var side = dir.cross(Vector3.UP).normalized() * w
			var tip = feet + dir * reach
			_ground_poly(camera, [feet - side, tip - side, tip + dir * w, tip + side, feet + side], fill, edge)
		_:
			_ground_circle(camera, feet, float(p.get("radius", 1.5)), fill, edge, 2.5)
	if not ready:
		var at = camera.unproject_position(feet + Vector3(0, 2.2, 0))
		var text = "%.1f" % abilities.get_ability_cooldown(ability)
		var font = UITheme.font_black()
		var w2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string_outline(font, at - Vector2(w2 / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.8))
		draw_string(font, at - Vector2(w2 / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))
	return true

# ---------------------------------------------------------------- where is my hero

## The view ran ahead of the hero (long guns): an arrow at the screen edge points back at them
func _draw_hero_locator(camera: Camera3D, head: Vector3, col: Color):
	var rect = Rect2(Vector2.ZERO, size).grow(-EDGE_MARGIN)
	var p = camera.unproject_position(head)
	if not camera.is_position_behind(head) and rect.has_point(p):
		return
	var center = size / 2.0
	var d = (p - center)
	if camera.is_position_behind(head):
		d = -d
	if d.length() < 1.0:
		return
	d = d.normalized()
	# Where the ray from the middle leaves the margin rectangle
	var t = INF
	if abs(d.x) > 0.001:
		t = min(t, (rect.size.x / 2.0) / abs(d.x))
	if abs(d.y) > 0.001:
		t = min(t, (rect.size.y / 2.0) / abs(d.y))
	var at = center + d * t
	var pulse = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 180.0)
	draw_circle(at, 17.0, Color(0.03, 0.05, 0.1, 0.8))
	draw_circle(at, 13.0, Color(col, pulse))
	var tip = at + d * 30.0
	var n = Vector2(-d.y, d.x) * 9.0
	draw_colored_polygon(PackedVector2Array([tip, at + d * 17.0 + n, at + d * 17.0 - n]), Color(col, pulse))
	var font = UITheme.font_black()
	var label = tr("YOU")
	var w = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, at + Vector2(-w / 2.0, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.03, 0.05, 0.1))

# ---------------------------------------------------------------- ground shapes (projected)

func _project(camera: Camera3D, points: Array) -> PackedVector2Array:
	var out = PackedVector2Array()
	for q in points:
		if camera.is_position_behind(q):
			return PackedVector2Array()
		out.append(camera.unproject_position(q))
	return out

func _ground_poly(camera: Camera3D, points: Array, fill: Color, edge: Color, width: float = 2.0):
	var pts = _project(camera, points)
	if pts.size() < 3:
		return
	if fill.a > 0.0 and Geometry2D.triangulate_polygon(pts).size() > 0:
		draw_colored_polygon(pts, fill)
	if edge.a > 0.0:
		var loop = pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, edge, width, true)

func _ground_circle(camera: Camera3D, c: Vector3, r: float, fill: Color, edge: Color, width: float = 2.0, dashed: bool = false):
	var n = clampi(int(r * 6.0), 24, 96)
	var points: Array = []
	for i in n:
		var a = TAU * i / n
		points.append(c + Vector3(cos(a) * r, 0, sin(a) * r))
	if not dashed:
		_ground_poly(camera, points, fill, edge, width)
		return
	var pts = _project(camera, points)
	if pts.size() < 3:
		return
	for i in range(0, pts.size(), 2):
		draw_line(pts[i], pts[(i + 1) % pts.size()], edge, width, true)

func _ground_sector(camera: Camera3D, c: Vector3, dir: Vector3, r: float, angle_deg: float, fill: Color, edge: Color):
	var half = deg_to_rad(angle_deg) / 2.0
	var steps = clampi(int(angle_deg / 5.0), 4, 24)
	var points: Array = [c]
	for i in steps + 1:
		var a = -half + 2.0 * half * i / steps
		points.append(c + dir.rotated(Vector3.UP, a) * r)
	_ground_poly(camera, points, fill, edge)

func _ground_line(camera: Camera3D, a: Vector3, b: Vector3, col: Color, width: float, dashed: bool):
	var pts = _project(camera, [a, b])
	if pts.size() < 2:
		return
	if not dashed:
		draw_line(pts[0], pts[1], col, width, true)
		return
	var dist = pts[0].distance_to(pts[1])
	var d = (pts[1] - pts[0]) / max(dist, 0.001)
	var s = 0.0
	while s < dist:
		draw_line(pts[0] + d * s, pts[0] + d * min(s + 8.0, dist), col, width, true)
		s += 15.0
