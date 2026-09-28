## Models and glow effects for loot containers and pickups.
## Props are built by tools/ai_models/blender/make_props.py (models/props/*.glb, paper low-poly
## look); a missing file falls back to a simple primitive so the game never breaks.
extends RefCounted
class_name LootVisuals

const PROPS_DIR := "res://models/props/"

## Colors of the loot beams / halos: what kind of loot it is, readable from far away
static func type_color(item_type: int) -> Color:
	match item_type:
		LootItem.ItemType.HEALTH:
			return Color(0.35, 1.0, 0.45)
		LootItem.ItemType.AMMO:
			return Color(1.0, 0.82, 0.3)
		LootItem.ItemType.WEAPON:
			return Color(1.0, 0.62, 0.18)
		LootItem.ItemType.ABILITY_BOOST:
			return Color(0.78, 0.45, 1.0)
		LootItem.ItemType.SHIELD:
			return Color(0.35, 0.65, 1.0)
	return Color(1, 1, 1)

static func container_file(type: int) -> String:
	match type:
		LootContainer.ContainerType.CHEST:
			return "chest"
		LootContainer.ContainerType.BARREL:
			return "barrel"
		LootContainer.ContainerType.SUPPLY_DROP:
			return "supply_drop"
	return "crate"

## Container model with its "Lid" (and "Parachute") child nodes, or null if the prop is missing
static func container_model(type: int) -> Node3D:
	return _instance(PROPS_DIR + container_file(type) + ".glb")

## Pickup model fitted to a comfortable on-ground size, centered on the origin
static func pickup_model(item_type: int, item_data: ItemData) -> Node3D:
	var path := ""
	var size := 0.5
	match item_type:
		LootItem.ItemType.HEALTH:
			path = "medkit"
		LootItem.ItemType.SHIELD:
			path = "shield"
			size = 0.55
		LootItem.ItemType.ABILITY_BOOST:
			path = "crystal"
			size = 0.55
		LootItem.ItemType.AMMO:
			path = _ammo_file(item_data)
			size = 0.42
		LootItem.ItemType.WEAPON:
			size = 0.9
			if item_data is RangedWeapon and item_data.model_path != "":
				var weapon = _instance(item_data.model_path)
				if weapon:
					fit(weapon, size)
					return weapon
	if path != "" and not path.begins_with("res://"):
		path = PROPS_DIR + path + ".glb"
	var model = _instance(path) if path != "" else null
	if model:
		fit(model, size)
	return model

## Harvest bonus (map event): a glowing bulb on a sprout, in the bonus color
static func harvest_model(color: Color) -> Node3D:
	var root = Node3D.new()
	var bulb = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.46
	sphere.radial_segments = 8
	sphere.rings = 5
	bulb.mesh = sphere
	var glow = StandardMaterial3D.new()
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 1.4
	glow.roughness = 0.3
	bulb.material_override = glow
	bulb.position.y = 0.08
	root.add_child(bulb)
	var leaf_mat = StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.32, 0.75, 0.28)
	for i in 3:
		var leaf = MeshInstance3D.new()
		var prism = PrismMesh.new()
		prism.size = Vector3(0.12, 0.28, 0.03)
		leaf.mesh = prism
		leaf.material_override = leaf_mat
		var a = TAU * i / 3.0
		leaf.position = Vector3(cos(a) * 0.07, 0.36, sin(a) * 0.07)
		leaf.rotation = Vector3(0.0, -a, 0.5)
		root.add_child(leaf)
	return root

## Ammo looks like the Blaster Kit's magazines and foam darts; fuel stays a canister (props)
static func _ammo_file(item_data: ItemData) -> String:
	if item_data is AmmoItem:
		match item_data.ammo_type:
			AmmoItem.AmmoType.SHOTGUN:
				return "res://models/bullet-foam-thick.glb"
			AmmoItem.AmmoType.SNIPER:
				return "res://models/bullet-foam-tip-thick.glb"
			AmmoItem.AmmoType.RIFLE:
				return "res://models/clip-large.glb"
			AmmoItem.AmmoType.FUEL:
				return "fuel_can"
			AmmoItem.AmmoType.GRENADE:
				return "res://models/grenade-b.glb"
	return "res://models/clip-small.glb"

static func _instance(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scene = load(path)
	if not scene is PackedScene:
		return null
	var node = scene.instantiate()
	ModelUtils.apply_lowpoly_look(node)
	return node

## Scale so the longest side is `size` and center the model on its holder's origin
static func fit(model: Node3D, size: float) -> void:
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b = ModelUtils._relative_xform(model, mi) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var s = size / max(box.size.x, box.size.y, box.size.z, 0.001)
	model.scale = Vector3.ONE * s
	model.position = -box.get_center() * s

## Soft glowing disc lying on the ground
static func halo(color: Color, radius: float) -> MeshInstance3D:
	var disc = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	disc.mesh = quad
	var mat = _additive(color)
	var tex = GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	tex.gradient = g
	mat.albedo_texture = tex
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return disc

## Vertical light pillar fading out upwards (loot beam)
static func beam(color: Color, height: float, radius: float) -> MeshInstance3D:
	var pillar = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = radius * 0.6
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 10
	cyl.cap_top = false
	cyl.cap_bottom = false
	pillar.mesh = cyl
	var mat = _additive(color)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tex = GradientTexture2D.new()
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var g = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])  # v = 0 at the bottom of the pillar
	g.colors = PackedColorArray([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	tex.gradient = g
	mat.albedo_texture = tex
	pillar.material_override = mat
	pillar.position.y = height / 2.0
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return pillar

static func _additive(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mat.no_depth_test = false
	return mat

## One-shot sparkle burst (little glinting stars)
static func sparkles(color: Color, amount: int, speed: float, lifetime: float = 0.9) -> GPUParticles3D:
	var p = GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.9
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 50.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -6, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var curve = Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	var curve_tex = CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	pm.color = color
	p.process_material = pm
	var quad = QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	quad.material = LandingImpact.soft_particle_material(true)
	p.draw_pass_1 = quad
	return p
