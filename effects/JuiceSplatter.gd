## Juice splatter: a spray when someone is hit, stains on the ground and nearby walls, footprints
## from heroes who walk through a puddle, and a juice tint on whoever stood point-blank.
## Visual only and local: it reacts to HealthComponent.damage_taken / hit_from, which every peer
## already gets for the players it can see (fog of war keeps hidden ones silent), so nothing new
## travels over the network. Skipped on headless / dedicated servers and when switched off in Settings.
extends Node3D
class_name JuiceSplatter

const MAX_STAINS: int = 160        # ring buffer: the oldest stain is recycled
const MAX_PARTICLES: int = 10
const STAIN_LIFE: float = 50.0
const PRINT_LIFE: float = 14.0
const FADE_TIME: float = 6.0
const POINT_BLANK: float = 3.0     # metres between shooter and victim that splashes the shooter
const TINT_LIFE: float = 12.0
const STEPS_AFTER_PUDDLE: int = 6

static var _instance: JuiceSplatter = null

var _stains: Array = []            # {node, mat, age, life, a0}
var _next: int = 0
var _particles: Array = []
var _next_particle: int = 0
var _disc: PlaneMesh = null
var _stain_shader: Shader = null
var _tint_shader: Shader = null
var _drop_shader: Shader = null
var _tints: Array = []             # {entity, mat, meshes, age}
var _puddles: Array = []           # {pos: Vector3, until: float}, recent ground stains (msec)
var _walkers: Dictionary = {}      # entity -> {last: Vector3, steps: int, left: bool}
var _walk_timer: float = 0.0

static func enabled() -> bool:
	if RenderQuality.level() == RenderQuality.LOW:
		return false
	return GameSettings.juice_splatter and DisplayServer.get_name() != "headless"

## Called when `entity` (Player / Weed) took damage. The spray flies away from `from_pos` if known.
static func hit(entity: Node3D, amount: float, color: Color, from_pos = null) -> void:
	if not enabled() or not is_instance_valid(entity) or not entity.is_inside_tree() or amount < 0.5:
		return
	var inst = _inst(entity)
	if inst:
		inst._on_hit(entity, amount, color, from_pos)

## Hook an entity's HealthComponent up to the splatter (Player and Weed call this in _ready)
static func watch(entity: Node3D, health) -> void:
	entity.set_meta("juice_born", Time.get_ticks_msec())
	if health == null or DisplayServer.get_name() == "headless":
		return
	health.hit_from.connect(func(pos, _amount):
		if fresh(entity):
			return
		entity.set_meta("juice_from", [pos, Time.get_ticks_msec()])
		var shooter = null
		var best = 0.6
		for p in entity.get_tree().get_nodes_in_group("players"):
			if p != entity and p is Node3D and p.global_position.distance_to(pos) < best:
				best = p.global_position.distance_to(pos)
				shooter = p
		if shooter:
			point_blank(entity, shooter, _color_of(entity)))
	# deferred: on the server hit_from comes right after damage_taken and carries the direction
	health.damage_taken.connect(func(amount, _source):
		_hit_later.call_deferred(entity, amount))

## Fog of war: a hidden victim must not spray or stain; a copy that just appeared gets its first
## health sync as a fake hit (ClientWorld spawns at full health), so the first 0.5 s don't count
static func fresh(entity: Node) -> bool:
	return Time.get_ticks_msec() - int(entity.get_meta("juice_born", 0)) < 500

static func hidden(entity: Node3D) -> bool:
	return not entity.is_visible_in_tree() or bool(entity.get_meta("net_hidden", false))

static func _color_of(entity: Node) -> Color:
	if entity.has_method("cfg"):
		return entity.cfg().color
	return AbilityFX.hero_color(entity)

static func _hit_later(entity: Node3D, amount: float) -> void:
	if not is_instance_valid(entity) or fresh(entity):
		return
	var from = null
	var info = entity.get_meta("juice_from", null)
	if info is Array and Time.get_ticks_msec() - int(info[1]) < 150:
		from = info[0]
	hit(entity, amount, _color_of(entity), from)

## `shooter` stood close to the victim: they get splashed too
static func point_blank(victim: Node3D, shooter: Node3D, color: Color) -> void:
	if not enabled() or not is_instance_valid(victim) or not is_instance_valid(shooter) or not shooter.is_inside_tree():
		return
	if hidden(victim) or victim.global_position.distance_to(shooter.global_position) > POINT_BLANK:
		return
	var inst = _inst(shooter)
	if inst:
		inst._tint(shooter, color)

static func _inst(near: Node) -> JuiceSplatter:
	if is_instance_valid(_instance) and _instance.is_inside_tree():
		return _instance
	var scene = near.get_tree().current_scene if near.is_inside_tree() else null
	if not (scene is Node3D):
		return null
	_instance = JuiceSplatter.new()
	_instance.name = "JuiceSplatter"
	scene.add_child(_instance)
	return _instance

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_disc = PlaneMesh.new()  # faces +Y, UV 0..1: the stain shader draws the blob on it
	_disc.size = Vector2(1, 1)
	_stain_shader = load("res://shaders/juice_stain.gdshader")
	_drop_shader = load("res://shaders/juice_drop.gdshader")
	_tint_shader = load("res://shaders/juice_tint.gdshader")

func _flat_mat(color: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

# ---------------------------------------------------------------- hit

func _on_hit(entity: Node3D, amount: float, color: Color, from_pos) -> void:
	if hidden(entity):
		return
	var chest = entity.global_position + Vector3(0, 0.9, 0)
	var away = Vector3.UP
	var flat = Vector3.ZERO
	if from_pos is Vector3:
		flat = entity.global_position - from_pos
		flat.y = 0.0
		if flat.length() > 0.05:
			flat = flat.normalized()
			away = (flat + Vector3.UP * 0.5).normalized()
		else:
			flat = Vector3.ZERO
	_burst(chest, away, color, clampi(12 + int(amount * 0.25), 12, 22), 62.0 if flat != Vector3.ZERO else 85.0)
	# Ground stains, thrown the way the spray goes
	var n = clampi(1 + int(amount / 12.0), 1, 3)
	var space = get_world_3d().direct_space_state
	for i in n:
		var ang = randf() * TAU
		var off = Vector3(cos(ang), 0, sin(ang)) * randf_range(0.1, 0.8) + flat * randf_range(0.2, 1.2)
		var p = entity.global_position + off
		var q = PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 4.0, 1)
		var r = space.intersect_ray(q)
		if r:
			var size = randf_range(0.5, 0.9) + minf(amount, 40.0) * 0.012
			_stain(r.position, r.normal, size, color, STAIN_LIFE)
			_puddles.append({"pos": r.position, "until": Time.get_ticks_msec() + 25000, "color": color})
	# Tarantino streak: a long thin smear along the hit direction, and a few far spots
	if flat != Vector3.ZERO:
		var sp = entity.global_position + flat * randf_range(1.0, 1.6)
		var sr = space.intersect_ray(PhysicsRayQueryParameters3D.create(sp + Vector3.UP * 2.0, sp + Vector3.DOWN * 4.0, 1))
		if sr:
			_stain(sr.position, sr.normal, randf_range(0.35, 0.5), color, STAIN_LIFE, flat, randf_range(2.4, 3.4), 2.0)
		if amount > 10.0:
			for k in 2:
				var fp = entity.global_position + flat * randf_range(1.6, 2.8) + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
				# appears when the drops land (~flight time)
				get_tree().create_timer(randf_range(0.25, 0.5)).timeout.connect(_land.bind(fp, color))
	if _puddles.size() > 24:
		_puddles = _puddles.slice(_puddles.size() - 24)
	# One splash on the nearest wall / prop
	var best = null
	var best_d = 1.9
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var wq = PhysicsRayQueryParameters3D.create(chest, chest + d * best_d, 1)
		var w = space.intersect_ray(wq)
		if w and absf(w.normal.y) < 0.5:
			var dist = chest.distance_to(w.position)
			if dist < best_d:
				best = w
				best_d = dist
	if best:
		_stain(best.position + Vector3(0, randf_range(-0.3, 0.2), 0), best.normal, randf_range(0.45, 0.8), color, STAIN_LIFE)

func _land(fp: Vector3, color: Color) -> void:
	if not is_inside_tree():
		return
	var fr = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(fp + Vector3.UP * 2.0, fp + Vector3.DOWN * 4.0, 1))
	if fr:
		_stain(fr.position, fr.normal, randf_range(0.12, 0.2), color, STAIN_LIFE * 0.6, Vector3.ZERO, 1.0, 0.0)

## Two crossed quads (so a drop is never edge-on), 0.1 wide and 0.5 long, centered; UV v = 0 on top
func _make_drop_mesh(mat: Material) -> ArrayMesh:
	var w = 0.05
	var l = 0.25
	var verts = PackedVector3Array([
		Vector3(-w, l, 0), Vector3(w, l, 0), Vector3(w, -l, 0), Vector3(-w, -l, 0),
		Vector3(0, l, -w), Vector3(0, l, w), Vector3(0, -l, w), Vector3(0, -l, -w)])
	var uvs = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var normals = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK,
		Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh

func _burst(pos: Vector3, dir: Vector3, color: Color, count: int, spread: float) -> void:
	var p: CPUParticles3D
	if _particles.size() < MAX_PARTICLES:
		p = CPUParticles3D.new()
		p.one_shot = true
		p.explosiveness = 1.0
		p.lifetime = 0.6
		p.gravity = Vector3(0, -14, 0)
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 5.5
		p.scale_amount_min = 0.5
		p.scale_amount_max = 2.2  # a few big blobs, many small
		# A thin low-poly drop, its long axis along the velocity: reads as a flying streak
		var dm = ShaderMaterial.new()
		dm.shader = _drop_shader
		p.mesh = _make_drop_mesh(dm)
		var curve = Curve.new()  # the drop thins out as it flies
		curve.add_point(Vector2(0, 1.0))
		curve.add_point(Vector2(1, 0.25))
		p.scale_amount_curve = curve
		p.set_particle_flag(CPUParticles3D.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
		add_child(p)
		_particles.append(p)
	else:
		p = _particles[_next_particle]
		_next_particle = (_next_particle + 1) % MAX_PARTICLES
	(p.mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("juice_color", color)
	p.amount = count
	p.direction = dir
	p.spread = spread
	p.global_position = pos
	p.restart()
	p.emitting = true

## dir: world direction a streak points (ZERO = random); stretch > 1 = a streak along it
func _stain(pos: Vector3, normal: Vector3, size: float, color: Color, life: float, dir: Vector3 = Vector3.ZERO, stretch: float = 1.0, drops: float = 5.0) -> void:
	var s: Dictionary
	if _stains.size() < MAX_STAINS:
		var node = MeshInstance3D.new()
		node.mesh = _disc
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat = ShaderMaterial.new()
		mat.shader = _stain_shader
		node.material_override = mat
		add_child(node)
		s = {"node": node, "mat": mat, "age": 0.0, "life": life, "a0": 0.0}
		_stains.append(s)
	else:
		s = _stains[_next]
		_next = (_next + 1) % MAX_STAINS
	var node3: MeshInstance3D = s.node
	# Lay the disc on the surface: its Y axis along the normal
	var up = normal.normalized()
	var ref = Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x = up.cross(ref).normalized()
	var streak = dir - up * dir.dot(up)
	if streak.length() > 0.01:
		x = streak.normalized()
	var z = x.cross(up).normalized()
	var big = size * 2.5 # the blob fills ~half of the quad, the rest is room for drops
	var basis = Basis(x * big * stretch, up, z * big)
	if streak.length() <= 0.01:
		basis = basis.rotated(up, randf() * TAU)
	node3.global_transform = Transform3D(basis, pos + up * 0.02 + up * randf() * 0.005)
	node3.visible = true
	s.age = 0.0
	s.life = life
	s.a0 = 1.0
	var c = color.darkened(randf_range(0.0, 0.2))
	var m: ShaderMaterial = s.mat
	m.set_shader_parameter("juice_color", c)
	m.set_shader_parameter("seed", randf())
	m.set_shader_parameter("drops", drops)
	m.set_shader_parameter("fade", 1.0)

# ---------------------------------------------------------------- hero staining

func _tint(entity: Node3D, color: Color) -> void:
	for t in _tints:
		if t.entity == entity:
			t.age = 0.0
			(t.mat as ShaderMaterial).set_shader_parameter("juice_color", color)
			(t.mat as ShaderMaterial).set_shader_parameter("amount", 1.0)
			return
	var meshes = entity.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	var mat = ShaderMaterial.new()
	mat.shader = _tint_shader
	mat.set_shader_parameter("juice_color", color)
	mat.set_shader_parameter("seed", randf() * 20.0)
	for m in meshes:
		(m as MeshInstance3D).material_overlay = mat
	_tints.append({"entity": entity, "mat": mat, "meshes": meshes, "age": 0.0, "color": color})
	# The walker leaves prints for a while
	_walkers[entity] = {"last": entity.global_position, "steps": STEPS_AFTER_PUDDLE, "left": false}

func _clear_tint(t: Dictionary) -> void:
	for m in t.meshes:
		if is_instance_valid(m) and (m as MeshInstance3D).material_overlay == t.mat:
			(m as MeshInstance3D).material_overlay = null

# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	for s in _stains:
		if s.life <= 0.0:
			continue
		s.age += delta
		if s.age >= s.life:
			s.life = 0.0
			s.node.visible = false
			continue
		var left = s.life - s.age
		if left < FADE_TIME:
			s.mat.set_shader_parameter("fade", s.a0 * left / FADE_TIME)
	for i in range(_tints.size() - 1, -1, -1):
		var t = _tints[i]
		t.age += delta
		if t.age >= TINT_LIFE or not is_instance_valid(t.entity):
			_clear_tint(t)
			_tints.remove_at(i)
			continue
		t.mat.set_shader_parameter("amount", 1.0 - t.age / TINT_LIFE)
	_walk_timer += delta
	if _walk_timer >= 0.1:
		_walk_timer = 0.0
		_update_walkers()

func _update_walkers() -> void:
	var now = Time.get_ticks_msec()
	while not _puddles.is_empty() and _puddles[0].until < now:
		_puddles.remove_at(0)
	for e in get_tree().get_nodes_in_group("players"):
		if not (e is Node3D) or not e.is_inside_tree() or not e.visible:
			continue
		var w = _walkers.get(e)
		var pos: Vector3 = e.global_position
		if w == null:
			if _puddles.is_empty():
				continue
			w = {"last": pos, "steps": 0, "left": false}
			_walkers[e] = w
		# Feet over a puddle: juiced up for the next few steps
		for pd in _puddles:
			if Vector2(pos.x - pd.pos.x, pos.z - pd.pos.z).length() < 0.6 and absf(pos.y - pd.pos.y) < 0.8:
				w.steps = STEPS_AFTER_PUDDLE
				w.color = pd.get("color", Color(0.9, 0.25, 0.2))
				break
		if w.steps > 0 and Vector2(pos.x - w.last.x, pos.z - w.last.z).length() > 0.7:
			var dir = pos - w.last
			dir.y = 0.0
			dir = dir.normalized()
			w.last = pos
			w.steps -= 1
			w.left = not w.left
			var side = Vector3(-dir.z, 0, dir.x) * (0.16 if w.left else -0.16)
			var col: Color = w.get("color", Color(0.9, 0.25, 0.2))
			_stain(pos + side + Vector3(0, 0.05, 0), Vector3.UP, 0.2, col.darkened(0.15), PRINT_LIFE, dir, 1.5, 0.0)
	# Forget freed entities
	for k in _walkers.keys():
		if not is_instance_valid(k):
			_walkers.erase(k)
