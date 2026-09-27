## Interactive hex map for the spawn selection screen.
## Draws every tile as a real hexagon, scaled to fit, with hover/selection/reserved states.
extends Control
class_name HexMapView

signal hex_clicked(coords: Vector2i)
signal hex_hovered(coords: Vector2i)

const INVALID = Vector2i(-9999, -9999)
const SQRT3 = 1.7320508

const BIOME_COLORS = {
	0: Color("5fae5a"),  # GRASS
	1: Color("2f7d4a"),  # FOREST
	2: Color("d9b772"),  # DESERT
	3: Color("8c8a92"),  # ROCK
	4: Color("3a78c9"),  # WATER
	5: Color("5aa5d8"),  # SHALLOW_WATER
	6: Color("6e7f45"),  # SWAMP
	7: Color("e6d39a"),  # BEACH
	8: Color("6d6774"),  # MOUNTAIN
}

var tiles: Dictionary = {}     # Vector2i -> {biome, spawnable}
var reserved: Dictionary = {}  # Vector2i -> true
var selected: Vector2i = INVALID
var hovered: Vector2i = INVALID
var accent: Color = Color(0.52, 0.91, 0.42)

var _hex_size: float = 10.0
var _origin: Vector2 = Vector2.ZERO
var _pulse: float = 0.0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_recompute_layout)

func _process(delta: float):
	if selected != INVALID:
		_pulse += delta * 3.0
		queue_redraw()

func set_tiles(data: Dictionary):
	tiles = data
	_recompute_layout()

func set_reserved(coords_list: Array):
	reserved.clear()
	for c in coords_list:
		reserved[c] = true
	queue_redraw()

func set_selected(coords: Vector2i):
	selected = coords
	queue_redraw()

func is_selectable(coords: Vector2i) -> bool:
	if not tiles.has(coords) or reserved.has(coords):
		return false
	var t = tiles[coords]
	return t.get("spawnable", t.get("biome", 0) != 4)

func biome_color(biome: int) -> Color:
	return BIOME_COLORS.get(biome, Color(0.5, 0.5, 0.5))

# ---------------------------------------------------------------- geometry

func _axial_to_unit(c: Vector2i) -> Vector2:
	return Vector2(SQRT3 * (c.x + c.y * 0.5), 1.5 * c.y)

func hex_to_pixel(c: Vector2i) -> Vector2:
	return _origin + _axial_to_unit(c) * _hex_size

func pixel_to_hex(p: Vector2) -> Vector2i:
	var local = (p - _origin) / _hex_size
	var q = (SQRT3 / 3.0 * local.x - 1.0 / 3.0 * local.y)
	var r = (2.0 / 3.0 * local.y)
	return _hex_round(q, r)

func _hex_round(qf: float, rf: float) -> Vector2i:
	var sf = -qf - rf
	var q = round(qf)
	var r = round(rf)
	var s = round(sf)
	var dq = abs(q - qf)
	var dr = abs(r - rf)
	var ds = abs(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))

func _recompute_layout():
	if tiles.is_empty() or size.x <= 0:
		queue_redraw()
		return
	var min_p = Vector2(INF, INF)
	var max_p = Vector2(-INF, -INF)
	for c in tiles.keys():
		var p = _axial_to_unit(c)
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var extent = (max_p - min_p) + Vector2(SQRT3, 2.0)
	_hex_size = min(size.x / extent.x, size.y / extent.y) * 0.96
	var center_unit = (min_p + max_p) / 2.0
	_origin = size / 2.0 - center_unit * _hex_size
	queue_redraw()

func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for i in 6:
		var angle = deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return pts

# ---------------------------------------------------------------- drawing

func _draw():
	if tiles.is_empty():
		return

	var inner = _hex_size * 0.92
	for c in tiles.keys():
		var t = tiles[c]
		var center = hex_to_pixel(c)
		var color = biome_color(t.get("biome", 0))
		var spawnable = t.get("spawnable", true)
		if not spawnable:
			color = color.darkened(0.35)
			color.a = 0.55
		if reserved.has(c):
			color = color.lerp(Color(1.0, 0.38, 0.40), 0.55)
		if c == hovered and is_selectable(c):
			color = color.lightened(0.35)
		draw_colored_polygon(_hex_points(center, inner), color)

	# Map center marker
	var mid = hex_to_pixel(Vector2i.ZERO)
	draw_arc(mid, _hex_size * 3.0, 0, TAU, 48, Color(1, 1, 1, 0.12), 1.5, true)

	if hovered != INVALID and tiles.has(hovered):
		var hp = _hex_points(hex_to_pixel(hovered), inner)
		hp.append(hp[0])
		draw_polyline(hp, Color(1, 1, 1, 0.85), 2.0, true)

	if selected != INVALID and tiles.has(selected):
		var sc = hex_to_pixel(selected)
		var glow = 0.5 + 0.5 * sin(_pulse)
		draw_circle(sc, _hex_size * (2.2 + glow * 0.6), Color(accent, 0.12 + 0.08 * glow))
		draw_colored_polygon(_hex_points(sc, inner), accent)
		var sp = _hex_points(sc, _hex_size * 1.25)
		sp.append(sp[0])
		draw_polyline(sp, Color.WHITE, 2.5, true)

# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent):
	if event is InputEventMouseMotion:
		var c = pixel_to_hex(event.position)
		if not tiles.has(c):
			c = INVALID
		if c != hovered:
			hovered = c
			queue_redraw()
			if c != INVALID:
				hex_hovered.emit(c)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c = pixel_to_hex(event.position)
		if tiles.has(c):
			hex_clicked.emit(c)
			accept_event()

func _notification(what: int):
	if what == NOTIFICATION_MOUSE_EXIT and hovered != INVALID:
		hovered = INVALID
		queue_redraw()
