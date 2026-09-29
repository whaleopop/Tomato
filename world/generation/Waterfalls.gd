## Little waterfalls where a lake or a river meets a terrace (MapGenerator adds them after the
## map is built): a spring bursts out of a rocky crack just under the grassy lip, arcs down into
## the water and churns a ring of foam with a bit of mist. Seeded from the map, looks only (no
## collision), gone when the plateau tile goes (zone, rift).
extends RefCounted
class_name Waterfalls

const SHADER = preload("res://shaders/waterfall.gdshader")
const MAX_FALLS: int = 8
const SPOUT_BELOW_LIP: float = 0.3   # the crack is this far under the plateau's top
const THROW: float = 1.5             # m/s the water leaves the rock with
const GRAVITY: float = 9.8

static var _materials: Dictionary = {}

static func build(grid: HexGrid, seed_value: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 5150
	var keys: Array = grid.tiles.keys()
	keys.sort()
	var candidates: Array = []  # [water tile, land tile]
	for c in keys:
		var water: HexTile = grid.get_tile(c)
		if not water or not water.is_water():
			continue
		for k in 6:
			var land = grid.get_tile(c + HexTile.EDGE_DIRECTIONS[k])
			if land and land.level >= 1 and not land.is_water() and not land.is_mountain() and not land.is_ramp():
				candidates.append([water, land])
	var used := {}
	var made = 0
	while made < MAX_FALLS and not candidates.is_empty():
		var pick = candidates.pop_at(rng.randi() % candidates.size())
		var land: HexTile = pick[1]
		if used.has(land.hex_coords):
			continue
		used[land.hex_coords] = true
		_make(grid, pick[0], land, rng)
		made += 1

static func _make(grid: HexGrid, water: HexTile, land: HexTile, rng: RandomNumberGenerator) -> void:
	var node = Node3D.new()
	node.name = "Waterfall_%d_%d" % [land.hex_coords.x, land.hex_coords.y]
	grid.add_child(node)
	var wp = grid.hex_to_world(water.hex_coords)
	var lp = grid.hex_to_world(land.hex_coords)
	var dir = (lp - wp).normalized()          # from the water towards the plateau
	var out = -dir                             # the way the water is thrown
	var side = Vector3(-dir.z, 0, dir.x)       # along the cliff
	var top_y = land.global_position.y + HexTile.HEX_HEIGHT * 0.5
	var water_y = water.global_position.y + HexTile.HEX_HEIGHT * 0.5
	var face = (wp + lp) * 0.5 + side * rng.randf_range(-0.4, 0.4)  # on the cliff face
	var spout = face + Vector3(0, top_y - SPOUT_BELOW_LIP, 0) + out * 0.04
	var width = rng.randf_range(0.45, 0.6)

	# The arc: thrown out, then falling; a ribbon across the cliff that widens as it drops
	var drop = spout.y - water_y
	var fall_time = sqrt(2.0 * max(drop, 0.2) / GRAVITY)
	var rows = 12
	var edge_l: Array = []
	var edge_r: Array = []
	for r in rows + 1:
		var t = fall_time * float(r) / rows
		var p = spout + out * THROW * t + Vector3.DOWN * 0.5 * GRAVITY * t * t
		var w = lerp(width, width * 1.5, float(r) / rows)
		edge_l.append(p - side * w * 0.5)
		edge_r.append(p + side * w * 0.5)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rows:
		var f0 = float(r) / rows
		var f1 = float(r + 1) / rows
		var tangent = (edge_l[r + 1] - edge_l[r]).normalized()
		var normal = side.cross(tangent).normalized()
		if normal.dot(out + Vector3.UP) < 0.0:
			normal = -normal
		var quad = [[edge_l[r], Vector2(0, f0)], [edge_r[r], Vector2(1, f0)], [edge_r[r + 1], Vector2(1, f1)],
			[edge_l[r], Vector2(0, f0)], [edge_r[r + 1], Vector2(1, f1)], [edge_l[r + 1], Vector2(0, f1)]]
		for v in quad:
			st.set_uv(v[1])
			st.set_normal(normal)
			st.add_vertex(v[0])
	var ribbon = MeshInstance3D.new()
	ribbon.mesh = st.commit()
	ribbon.material_override = _material("fall")
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(ribbon)
	var landing = edge_l[rows].lerp(edge_r[rows], 0.5)

	# The crack it comes out of: a dark hollow framed by mossy rocks
	var hollow = MeshInstance3D.new()
	var hm = SphereMesh.new()
	hm.radius = width * 0.55
	hm.height = width * 0.8
	hm.radial_segments = 8
	hm.rings = 4
	hollow.mesh = hm
	hollow.material_override = _plain("hollow", Color(0.12, 0.1, 0.09))
	hollow.position = spout - out * 0.12
	node.add_child(hollow)
	var rock_spots = [
		spout + side * (width * 0.75) + Vector3(0, -0.05, 0),
		spout - side * (width * 0.75) + Vector3(0, 0.02, 0),
		spout + Vector3(0, SPOUT_BELOW_LIP * 0.9, 0) + side * rng.randf_range(-0.2, 0.2) - out * 0.05,
		landing + side * (width * 1.1) + Vector3(0, -0.05, 0),
		landing - side * (width * 1.2) - out * 0.2 + Vector3(0, -0.08, 0),
	]
	for i in rock_spots.size():
		var rock = MeshInstance3D.new()
		var rm = SphereMesh.new()
		var s = rng.randf_range(0.2, 0.32) * (1.25 if i >= 3 else 1.0)
		rm.radius = s
		rm.height = s * 1.5
		rm.radial_segments = 7
		rm.rings = 4
		rock.mesh = rm
		rock.material_override = _plain("rock%d" % (i % 2), Color(0.5, 0.49, 0.46) if i % 2 == 0 else Color(0.44, 0.48, 0.38))
		rock.position = rock_spots[i]
		rock.rotation = Vector3(rng.randf() * 0.6, rng.randf() * TAU, rng.randf() * 0.6)
		node.add_child(rock)

	# Churned foam where it lands
	var pool = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	pool.mesh = pm
	pool.material_override = _material("pool")
	pool.position = Vector3(landing.x, water_y + 0.015, landing.z)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(pool)

	# Mist rising from the foot
	var mist = GPUParticles3D.new()
	mist.amount = 14
	mist.lifetime = 1.8
	var mp = ParticleProcessMaterial.new()
	mp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mp.emission_sphere_radius = width * 0.6
	mp.direction = Vector3.UP
	mp.spread = 35.0
	mp.initial_velocity_min = 0.4
	mp.initial_velocity_max = 0.9
	mp.gravity = Vector3(0, -0.4, 0)
	mp.scale_min = 0.7
	mp.scale_max = 1.6
	mp.color = Color(1, 1, 1, 0.45)
	var fade = Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.25, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	var fade_tex = CurveTexture.new()
	fade_tex.curve = fade
	mp.alpha_curve = fade_tex
	mist.process_material = mp
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(0.55, 0.55)
	var qm = StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = FireTrail._soft_dot(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	quad_mesh.material = qm
	mist.draw_pass_1 = quad_mesh
	mist.position = landing + Vector3(0, 0.1, 0)
	node.add_child(mist)

	node.add_to_group("waterfalls")  # AmbientSound: water you can hear
	node.set_meta("sound_at", landing)
	land.tile_destroyed.connect(func(): if is_instance_valid(node): node.queue_free())

static func _material(mode: String) -> ShaderMaterial:
	if not _materials.has(mode):
		var m = ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("pool", 1.0 if mode == "pool" else 0.0)
		_materials[mode] = m
	return _materials[mode]

static func _plain(key: String, color: Color) -> StandardMaterial3D:
	if not _materials.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 1.0
		_materials[key] = m
	return _materials[key]
