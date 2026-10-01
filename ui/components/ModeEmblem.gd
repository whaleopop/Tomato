## The drawn emblem of a match mode (ModeCard): a shrinking hex island, a dandelion, a waving flag,
## a crown on a platform - lines and shapes in one style, softly animated, with a glow under them.
extends Control
class_name ModeEmblem

var mode: String = GameModes.BR
var color: Color = Color(1, 1, 1)
var pulse: float = 0.0      # 0..1: the chosen card's emblem moves a little more

const INK := Color(1.0, 0.98, 0.94)

func _process(_delta: float):
	queue_redraw()

func _draw():
	var c = size * 0.5
	var r = min(size.x, size.y) * 0.5
	var t = Time.get_ticks_msec() / 1000.0
	match mode:
		GameModes.BR:
			_island(c, r, t)
		GameModes.SURVIVORS:
			_dandelion(c, r, t)
		GameModes.CTF:
			_flag(c, r, t)
		GameModes.KOTH:
			_crown(c, r, t)

## A line twice: wide and faint (the glow), then the line itself
func _line(points: PackedVector2Array, col: Color, width: float, closed: bool = false) -> void:
	if closed:
		points.append(points[0])
	draw_polyline(points, Color(color, 0.25), width * 2.6, true)
	draw_polyline(points, col, width, true)

func _hex(center: Vector2, radius: float, rot: float = 0.0, squash: float = 1.0) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for i in 6:
		var a = rot + PI / 6.0 + i * PI / 3.0
		pts.append(center + Vector2(cos(a), sin(a) * squash) * radius)
	return pts

# Battle royale: three hex rings closing in, arrows pointing to the middle
func _island(c: Vector2, r: float, t: float) -> void:
	var breathe = 1.0 + sin(t * 1.6) * (0.02 + 0.03 * pulse)
	_line(_hex(c, r * 0.9 * breathe), Color(INK, 0.35), 8.0, true)
	_line(_hex(c, r * 0.62 * breathe), Color(INK, 0.7), 10.0, true)
	draw_colored_polygon(_hex(c, r * 0.34), Color(color, 0.25))
	_line(_hex(c, r * 0.34), INK, 12.0, true)
	draw_circle(c, r * 0.08, color.lightened(0.3))
	for i in 6:
		var a = i * PI / 3.0
		var dir = Vector2(cos(a), sin(a))
		var tip = c + dir * r * (0.7 + 0.04 * sin(t * 3.0 + i))
		var back = tip + dir * r * 0.1
		var side = dir.orthogonal() * r * 0.07
		_line(PackedVector2Array([back + side, tip, back - side]), Color(color.lightened(0.3), 0.95), 7.0)

# Weed Swarm: a dandelion head of spikes on a stem with jagged leaves
func _dandelion(c: Vector2, r: float, t: float) -> void:
	var head = c + Vector2(0, -r * 0.22)
	var stem = PackedVector2Array()
	for i in 9:
		var k = i / 8.0
		stem.append(head + Vector2(sin(k * 2.4 + t) * r * 0.05 * k, k * r * 0.95))
	_line(stem, Color(INK, 0.85), 9.0)
	for s in [-1.0, 1.0]:
		var base = head + Vector2(0, r * 0.62)
		var leaf = PackedVector2Array([base])
		for i in 5:
			var k = (i + 1) / 5.0
			var out = s * r * (0.42 * sin(k * PI) + 0.05) * (1.0 if i % 2 == 0 else 0.7)
			leaf.append(base + Vector2(out, -k * r * 0.34))
		_line(leaf, Color(color.lightened(0.2), 0.9), 7.0)
	var spin = t * (0.25 + 0.4 * pulse)
	for i in 14:
		var a = spin + i * TAU / 14.0
		var dir = Vector2(cos(a), sin(a))
		var spike = r * (0.5 + 0.05 * sin(t * 2.0 + i * 1.7))
		var p1 = head + dir * r * 0.2
		var p2 = head + dir * spike
		_line(PackedVector2Array([p1, p2]), Color(INK, 0.9), 5.0)
		draw_circle(p2, r * 0.035, color.lightened(0.35))
	draw_circle(head, r * 0.21, Color(color, 0.3))
	draw_arc(head, r * 0.2, 0.0, TAU, 40, INK, 10.0, true)
	draw_circle(head, r * 0.08, color.lightened(0.3))

# Capture the flag: a pole on a base hex, the flag waving
func _flag(c: Vector2, r: float, t: float) -> void:
	var foot = c + Vector2(-r * 0.3, r * 0.72)
	var top = foot + Vector2(0, -r * 1.42)
	draw_colored_polygon(_hex(foot, r * 0.42, 0.0, 0.38), Color(color, 0.22))
	_line(_hex(foot, r * 0.42, 0.0, 0.38), Color(INK, 0.6), 7.0, true)
	var wave = 1.0 + pulse
	var upper = PackedVector2Array()
	var lower = PackedVector2Array()
	for i in 13:
		var k = i / 12.0
		var x = top.x + k * r * 0.95
		var y = sin(k * 5.0 - t * 4.0 * wave) * r * 0.07 * k
		upper.append(Vector2(x, top.y + r * 0.04 + y))
		lower.append(Vector2(x, top.y + r * 0.58 + y))
	var body = upper.duplicate()
	var rev = lower.duplicate()
	rev.reverse()
	body.append_array(rev)
	draw_colored_polygon(body, Color(color, 0.85))
	var outline = body.duplicate()
	_line(outline, INK, 8.0, true)
	# A star on the cloth
	var mid = (upper[6] + lower[6]) * 0.5
	var star = PackedVector2Array()
	for i in 10:
		var a = -PI / 2.0 + i * PI / 5.0
		star.append(mid + Vector2(cos(a), sin(a)) * r * (0.13 if i % 2 == 0 else 0.055))
	draw_colored_polygon(star, INK)
	_line(PackedVector2Array([foot, top]), INK, 11.0)
	draw_circle(top, r * 0.05, color.lightened(0.4))

# King of the hill: a crown over a glowing platform
func _crown(c: Vector2, r: float, t: float) -> void:
	var plat = c + Vector2(0, r * 0.55)
	draw_colored_polygon(_hex(plat, r * 0.8, 0.0, 0.32), Color(color, 0.25))
	_line(_hex(plat, r * 0.8, 0.0, 0.32), Color(INK, 0.55), 7.0, true)
	_line(_hex(plat, r * 0.5, 0.0, 0.32), Color(color.lightened(0.3), 0.8), 6.0, true)
	var lift = sin(t * 2.0) * r * (0.03 + 0.04 * pulse)
	var b = c + Vector2(0, r * 0.12 + lift)
	var w = r * 0.62
	var h = r * 0.62
	var crown = PackedVector2Array([
		b + Vector2(-w, 0), b + Vector2(-w * 1.08, -h), b + Vector2(-w * 0.5, -h * 0.45),
		b + Vector2(0, -h * 1.2), b + Vector2(w * 0.5, -h * 0.45), b + Vector2(w * 1.08, -h), b + Vector2(w, 0)])
	draw_colored_polygon(crown, Color(color, 0.8))
	_line(crown, INK, 9.0, true)
	_line(PackedVector2Array([b + Vector2(-w, -h * 0.14), b + Vector2(w, -h * 0.14)]), Color(INK, 0.8), 6.0)
	for p in [b + Vector2(-w * 1.08, -h), b + Vector2(0, -h * 1.2), b + Vector2(w * 1.08, -h)]:
		draw_circle(p, r * 0.07, INK)
		draw_circle(p, r * 0.04, color.lightened(0.4))
