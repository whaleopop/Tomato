## Cosmetics: hero skins (a recolor through the paper shader's instance uniforms, so heroes still
## share one material), hats (small procedural models on top of the head) and weapon finishes
## (tinted copies of the gun's materials). Looks only - no stats. Ids are sent over the network
## (Player.cosmetics), names are English source strings (LocaleRu translates them).
extends RefCounted
class_name Cosmetics

## hsv: hue shift (turns), saturation and value multipliers; tint multiplies; metal 0..1;
## glow: rim light color (alpha = strength); pattern: [kind, scale, color] from
## shaders/patterns.gdshaderinc (1 stripes, 2 dots, 3 camo, 4 checker, 5 zebra, 6 galaxy, 7 waves)
const SKINS = {
	"classic": {"name": "Classic", "price": 0, "hsv": Vector3(0, 1, 1), "tint": Color(1, 1, 1), "metal": 0.0, "glow": Color(0, 0, 0, 0)},
	"candy": {"name": "Candy", "price": 200, "hsv": Vector3(0.5, 1.1, 1.05), "tint": Color(1, 0.9, 1), "metal": 0.0, "glow": Color(1, 0.5, 0.8, 0.25)},
	"frost": {"name": "Frost", "price": 250, "hsv": Vector3(0.0, 0.35, 1.1), "tint": Color(0.75, 0.9, 1.1), "metal": 0.15, "glow": Color(0.6, 0.85, 1.0, 0.35)},
	"zombie": {"name": "Zombie", "price": 250, "hsv": Vector3(0.0, 0.45, 0.8), "tint": Color(0.75, 1.0, 0.6), "metal": 0.0, "glow": Color(0.4, 1.0, 0.3, 0.2)},
	"shadow": {"name": "Shadow", "price": 300, "hsv": Vector3(0.0, 0.6, 0.35), "tint": Color(0.8, 0.75, 1.0), "metal": 0.0, "glow": Color(0.6, 0.35, 1.0, 0.45)},
	"neon": {"name": "Neon", "price": 400, "hsv": Vector3(0.0, 1.6, 1.15), "tint": Color(1, 1, 1), "metal": 0.0, "glow": Color(0.2, 1.0, 0.9, 0.7)},
	"golden": {"name": "Golden", "price": 500, "hsv": Vector3(0.0, 0.2, 1.1), "tint": Color(1.25, 0.95, 0.45), "metal": 0.85, "glow": Color(1.0, 0.8, 0.3, 0.25)},
	"polka": {"name": "Polka Dots", "price": 250, "hsv": Vector3(0, 1, 1), "tint": Color(1, 1, 1), "metal": 0.0, "glow": Color(0, 0, 0, 0), "pattern": [2, 7.0, Color(1, 1, 1, 0.9)]},
	"tiger": {"name": "Tiger", "price": 350, "hsv": Vector3(0.0, 1.2, 1.05), "tint": Color(1.1, 0.85, 0.6), "metal": 0.0, "glow": Color(0, 0, 0, 0), "pattern": [1, 5.0, Color(0.08, 0.05, 0.03, 0.95)]},
	"zebra": {"name": "Zebra", "price": 350, "hsv": Vector3(0.0, 0.0, 1.3), "tint": Color(1, 1, 1), "metal": 0.0, "glow": Color(0, 0, 0, 0), "pattern": [5, 4.0, Color(0.06, 0.06, 0.07, 1.0)]},
	"camo": {"name": "Camo", "price": 300, "hsv": Vector3(0.0, 0.3, 0.8), "tint": Color(0.7, 0.85, 0.55), "metal": 0.0, "glow": Color(0, 0, 0, 0), "pattern": [3, 3.5, Color(0.25, 0.3, 0.15, 0.9)]},
	"checker": {"name": "Checkers", "price": 300, "hsv": Vector3(0, 1, 1), "tint": Color(1, 1, 1), "metal": 0.0, "glow": Color(0, 0, 0, 0), "pattern": [4, 5.0, Color(0.1, 0.1, 0.12, 0.85)]},
	"waves": {"name": "Waves", "price": 300, "hsv": Vector3(0.55, 1.0, 1.0), "tint": Color(1, 1, 1), "metal": 0.0, "glow": Color(0, 0, 0, 0), "pattern": [7, 2.5, Color(1.0, 0.95, 0.85, 0.8)]},
	"galaxy": {"name": "Galaxy", "price": 650, "hsv": Vector3(0.7, 1.2, 0.35), "tint": Color(0.8, 0.7, 1.2), "metal": 0.1, "glow": Color(0.5, 0.3, 1.0, 0.5), "pattern": [6, 3.0, Color(0.35, 0.15, 0.6, 0.8)]},
	# Mastery (Mastery.gd): not sold - a hero earns each one by reaching its rank
	"m_bronze": {"name": "Bronze Mastery", "price": 0, "mastery": 0, "hsv": Vector3(0.0, 0.35, 0.95), "tint": Color(1.15, 0.72, 0.42), "metal": 0.75, "glow": Color(1.0, 0.55, 0.25, 0.15)},
	"m_silver": {"name": "Silver Mastery", "price": 0, "mastery": 1, "hsv": Vector3(0.0, 0.08, 1.15), "tint": Color(0.95, 0.98, 1.08), "metal": 0.9, "glow": Color(0.8, 0.9, 1.0, 0.2)},
	"m_gold": {"name": "Gold Mastery", "price": 0, "mastery": 2, "hsv": Vector3(0.0, 0.15, 1.15), "tint": Color(1.35, 1.0, 0.4), "metal": 0.95, "glow": Color(1.0, 0.8, 0.3, 0.35), "pattern": [1, 9.0, Color(1.0, 0.9, 0.55, 0.25)]},
	"m_obsidian": {"name": "Obsidian Mastery", "price": 0, "mastery": 3, "hsv": Vector3(0.0, 0.3, 0.28), "tint": Color(0.75, 0.6, 1.0), "metal": 0.6, "glow": Color(0.6, 0.3, 1.0, 0.65), "pattern": [6, 4.0, Color(0.55, 0.2, 1.0, 0.7)]},
	"m_diamond": {"name": "Diamond Mastery", "price": 0, "mastery": 4, "hsv": Vector3(0.0, 0.25, 1.3), "tint": Color(0.75, 1.0, 1.25), "metal": 0.55, "glow": Color(0.5, 0.95, 1.0, 0.75), "pattern": [4, 9.0, Color(1.0, 1.0, 1.0, 0.45)]},
}
const HATS = {
	"no_hat": {"name": "No Hat", "price": 0},
	"party": {"name": "Party Hat", "price": 100},
	"cap": {"name": "Cap", "price": 150},
	"top_hat": {"name": "Top Hat", "price": 300},
	"horns": {"name": "Horns", "price": 350},
	"halo": {"name": "Halo", "price": 450},
	"crown": {"name": "Crown", "price": 600},
}
const WEAPON_SKINS = {
	"default": {"name": "Factory", "price": 0},
	"candy": {"name": "Candy", "price": 150, "tint": Color(1.0, 0.55, 0.8), "metal": 0.1, "rough": 0.5, "glow": Color(0, 0, 0)},
	"camo": {"name": "Camo", "price": 200, "tint": Color(0.6, 0.72, 0.42), "metal": 0.0, "rough": 0.9, "glow": Color(0, 0, 0), "pattern": [3, 8.0, Color(0.22, 0.26, 0.12, 0.95)]},
	"tiger": {"name": "Tiger", "price": 300, "tint": Color(1.3, 0.75, 0.3), "metal": 0.1, "rough": 0.5, "glow": Color(0, 0, 0), "pattern": [1, 9.0, Color(0.06, 0.04, 0.02, 1.0)]},
	"zebra": {"name": "Zebra", "price": 300, "tint": Color(1.4, 1.4, 1.4), "metal": 0.0, "rough": 0.6, "glow": Color(0, 0, 0), "pattern": [5, 9.0, Color(0.05, 0.05, 0.06, 1.0)]},
	"checker": {"name": "Checkers", "price": 250, "tint": Color(1.2, 1.2, 1.2), "metal": 0.2, "rough": 0.4, "glow": Color(0, 0, 0), "pattern": [4, 12.0, Color(0.08, 0.08, 0.1, 0.9)]},
	"dots": {"name": "Polka Dots", "price": 200, "tint": Color(1.0, 0.45, 0.45), "metal": 0.0, "rough": 0.5, "glow": Color(0, 0, 0), "pattern": [2, 14.0, Color(1, 1, 1, 0.95)]},
	"galaxy": {"name": "Galaxy", "price": 500, "tint": Color(0.35, 0.25, 0.6), "metal": 0.3, "rough": 0.3, "glow": Color(0.15, 0.05, 0.3), "pattern": [6, 7.0, Color(0.5, 0.25, 0.9, 0.8)]},
	"ice": {"name": "Ice", "price": 200, "tint": Color(0.65, 0.9, 1.2), "metal": 0.3, "rough": 0.15, "glow": Color(0.2, 0.45, 0.6)},
	"shadow": {"name": "Shadow", "price": 250, "tint": Color(0.35, 0.3, 0.45), "metal": 0.4, "rough": 0.35, "glow": Color(0.25, 0.1, 0.45)},
	"neon": {"name": "Neon", "price": 300, "tint": Color(0.5, 1.2, 1.1), "metal": 0.0, "rough": 0.4, "glow": Color(0.1, 0.8, 0.7)},
	"gold": {"name": "Gold", "price": 400, "tint": Color(1.3, 0.95, 0.4), "metal": 0.95, "rough": 0.2, "glow": Color(0, 0, 0)},
	# Mastery camos (Mastery.gd): earned per gun by using it, put on that gun only
	"m_bronze": {"name": "Bronze Mastery", "price": 0, "mastery": 0, "tint": Color(1.1, 0.68, 0.4), "metal": 0.85, "rough": 0.3, "glow": Color(0, 0, 0)},
	"m_silver": {"name": "Silver Mastery", "price": 0, "mastery": 1, "tint": Color(1.0, 1.02, 1.1), "metal": 0.95, "rough": 0.18, "glow": Color(0, 0, 0)},
	"m_gold": {"name": "Gold Mastery", "price": 0, "mastery": 2, "tint": Color(1.4, 1.0, 0.38), "metal": 1.0, "rough": 0.12, "glow": Color(0.25, 0.15, 0.0), "pattern": [1, 16.0, Color(1.0, 0.92, 0.6, 0.3)]},
	"m_obsidian": {"name": "Obsidian Mastery", "price": 0, "mastery": 3, "tint": Color(0.2, 0.15, 0.3), "metal": 0.7, "rough": 0.1, "glow": Color(0.35, 0.1, 0.7), "pattern": [6, 8.0, Color(0.6, 0.25, 1.0, 0.85)]},
	"m_diamond": {"name": "Diamond Mastery", "price": 0, "mastery": 4, "tint": Color(0.8, 1.1, 1.35), "metal": 0.6, "rough": 0.05, "glow": Color(0.2, 0.55, 0.7), "pattern": [4, 18.0, Color(1.0, 1.0, 1.0, 0.55)]},
}

static func catalog(kind: String) -> Dictionary:
	match kind:
		"skin":
			return SKINS
		"hat":
			return HATS
	return WEAPON_SKINS

## Heroes are bought too (a new player picks PlayerProfile.STARTER_PICKS of them for free)
const HERO_PRICES = {
	"Tomato": 500, "Carrot": 500, "Corn": 600, "Broccoli": 600, "Beet": 600, "Lemon": 700,
	"Banana": 700, "Pumpkin": 800, "Pepper": 800, "Apple": 800, "Grape": 900, "Watermelon": 900,
	"Pineapple": 900,
}

static func hero_id(hero: String) -> String:
	return "hero:" + hero

## "hero", "skin", "hat" or "weapon" (weapon skin ids are prefixed in the profile: see weapon_id)
static func kind_of(id: String) -> String:
	if id.begins_with("hero:"):
		return "hero"
	if id.begins_with("w_") or id == "default":
		return "weapon"
	if HATS.has(id):
		return "hat"
	return "skin"

## Weapon finishes share names with skins ("candy"), so their profile / network id is "w_<id>"
static func weapon_id(finish: String) -> String:
	return "default" if finish == "default" else "w_" + finish

static func _entry(id: String) -> Dictionary:
	if id.begins_with("hero:"):
		var hero = id.substr(5)
		return {"name": hero, "price": HERO_PRICES.get(hero, 700)} if CharacterRegistry.get_by_name(hero) else {}
	if id.begins_with("w_"):
		return WEAPON_SKINS.get(id.substr(2), {})
	if id == "default":
		return WEAPON_SKINS.default
	if HATS.has(id):
		return HATS[id]
	return SKINS.get(id, {})

## Rarity tier from the price (card frames): 0 common .. 3 legendary (mastery: legendary)
static func tier_of(id: String) -> int:
	if is_mastery(id):
		return 3
	var price = price_of(id)
	if id.begins_with("hero:"):
		return 2 if price >= 800 else 1
	if price >= 500:
		return 3
	if price >= 300:
		return 2
	if price >= 150:
		return 1
	return 0

const TIER_NAMES = ["Common", "Rare", "Epic", "Legendary"]
const TIER_COLORS = [Color(0.72, 0.78, 0.88), Color(0.35, 0.65, 1.0), Color(0.72, 0.42, 1.0), Color(1.0, 0.72, 0.25)]

## Earned, not bought (Mastery.gd)
static func is_mastery(id: String) -> bool:
	return Mastery.tier_of_id(id) >= 0

static func price_of(id: String) -> int:
	var e = _entry(id)
	return int(e.get("price", -1)) if not e.is_empty() else -1

static func name_of(id: String) -> String:
	return String(_entry(id).get("name", id))

# ---------------------------------------------------------------- heroes

## Recolor every mesh of a hero model and put the hat on (Player "Model", or a showcase model)
static func apply_to_character(root: Node3D, skin_id: String, hat_id: String) -> void:
	if not root or not is_instance_valid(root):
		return
	var s: Dictionary = SKINS.get(skin_id, SKINS.classic)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.get_meta("cosmetic", false):
			continue  # the hat itself
		mi.set_instance_shader_parameter("skin_hsv", s.hsv)
		mi.set_instance_shader_parameter("skin_tint", s.tint)
		mi.set_instance_shader_parameter("skin_metal", s.metal)
		mi.set_instance_shader_parameter("skin_glow", s.glow)
		var pat: Array = s.get("pattern", [0, 1.0, Color(0, 0, 0, 0)])
		mi.set_instance_shader_parameter("skin_pattern", Vector2(pat[0], pat[1]))
		mi.set_instance_shader_parameter("skin_pattern_color", pat[2])
	for old in root.find_children("CosmeticHat*", "", true, false):
		if is_instance_valid(old):  # the hat under a freed mount is gone already
			old.free()
	if hat_id == "" or hat_id == "no_hat" or not HATS.has(hat_id):
		return
	var box = _bounds(root)
	if box.size == Vector3.ZERO:
		return
	var hat = make_hat(hat_id)
	hat.name = "CosmeticHat"
	var width = max(box.size.x, box.size.z)
	var top = Vector3(box.get_center().x, box.end.y - 0.18 * box.size.y, box.get_center().z)
	var placed = Transform3D(Basis().scaled(Vector3.ONE * clamp(width / 0.7, 0.5, 1.6)), top)
	# Rigged heroes: ride on the head bone, so the hat moves with every animation
	var skeleton = root.find_children("*", "Skeleton3D", true, false)
	var head = skeleton[0].find_bone("head") if not skeleton.is_empty() else -1
	if head >= 0:
		var mount = BoneAttachment3D.new()
		mount.name = "CosmeticHatMount"
		mount.bone_name = "head"
		skeleton[0].add_child(mount)
		var bone_in_root = ModelUtils._relative_xform(root, skeleton[0]) * skeleton[0].get_bone_global_rest(head)
		hat.transform = bone_in_root.affine_inverse() * placed
		mount.add_child(hat)
	else:
		hat.transform = placed
		root.add_child(hat)

static func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.get_meta("cosmetic", false):
			continue
		var b = ModelUtils._relative_xform(root, mi) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

## A small hat model, about 0.45 wide, standing on y = 0
static func make_hat(id: String) -> Node3D:
	var hat = Node3D.new()
	match id:
		"party":
			_part(hat, _cone(0.2, 0.5), Vector3(0, 0.25, 0), _mat(Color(1.0, 0.35, 0.55)))
			_part(hat, _ball(0.07), Vector3(0, 0.52, 0), _mat(Color(1.0, 0.9, 0.3)))
		"cap":
			_part(hat, _dome(0.24, 0.16), Vector3(0, 0.0, 0), _mat(Color(0.25, 0.5, 1.0)))
			_part(hat, _box(Vector3(0.3, 0.03, 0.22)), Vector3(0, 0.02, 0.24), _mat(Color(0.2, 0.4, 0.9)))
		"top_hat":
			_part(hat, _cyl(0.3, 0.3, 0.04), Vector3(0, 0.02, 0), _mat(Color(0.12, 0.12, 0.15)))
			_part(hat, _cyl(0.18, 0.18, 0.36), Vector3(0, 0.2, 0), _mat(Color(0.12, 0.12, 0.15)))
			_part(hat, _cyl(0.185, 0.185, 0.06), Vector3(0, 0.07, 0), _mat(Color(0.8, 0.15, 0.2)))
		"horns":
			for side in [-1, 1]:
				var horn = _part(hat, _cone(0.07, 0.3), Vector3(side * 0.16, 0.12, 0), _mat(Color(0.95, 0.9, 0.8)))
				horn.rotation.z = -side * 0.5
		"halo":
			var ring = _part(hat, _torus(0.2, 0.26), Vector3(0, 0.3, 0), _glow_mat(Color(1.0, 0.9, 0.4)))
			ring.rotation.x = 0.15
		"crown":
			_part(hat, _cyl(0.22, 0.2, 0.12), Vector3(0, 0.06, 0), _mat(Color(1.0, 0.8, 0.25), 0.9))
			for i in 5:
				var a = TAU * i / 5.0
				_part(hat, _cone(0.05, 0.14), Vector3(cos(a) * 0.19, 0.18, sin(a) * 0.19), _mat(Color(1.0, 0.8, 0.25), 0.9))
				_part(hat, _ball(0.03), Vector3(cos(a) * 0.2, 0.08, sin(a) * 0.2), _mat(Color(0.9, 0.2, 0.3)))
	return hat

static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.set_meta("cosmetic", true)
	parent.add_child(mi)
	return mi

static func _mat(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = 0.35 if metal > 0.5 else 0.7
	return m

static func _glow_mat(color: Color) -> StandardMaterial3D:
	var m = _mat(color)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.5
	return m

static func _cone(radius: float, height: float) -> CylinderMesh:
	var c = CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 10
	return c

static func _cyl(top: float, bottom: float, height: float) -> CylinderMesh:
	var c = CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 14
	return c

static func _ball(radius: float) -> SphereMesh:
	var s = SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 8
	s.rings = 4
	return s

static func _dome(radius: float, height: float) -> SphereMesh:
	var s = SphereMesh.new()
	s.radius = radius
	s.height = height * 2.0
	s.is_hemisphere = true
	s.radial_segments = 12
	s.rings = 4
	return s

static func _box(size: Vector3) -> BoxMesh:
	var b = BoxMesh.new()
	b.size = size
	return b

static func _torus(inner: float, outer: float) -> TorusMesh:
	var t = TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	return t

# ---------------------------------------------------------------- weapons

## Tint a gun model's materials (a fresh model each time: WeaponVisualComponent, showcases)
static func apply_to_weapon(root: Node3D, finish_id: String) -> void:
	var finish = finish_id.substr(2) if finish_id.begins_with("w_") else finish_id
	if not root or finish == "" or finish == "default" or not WEAPON_SKINS.has(finish):
		return
	var w: Dictionary = WEAPON_SKINS[finish]
	var pat: Array = w.get("pattern", [0, 1.0, Color(0, 0, 0, 0)])
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not mi.mesh:
			continue
		for i in mi.mesh.get_surface_count():
			# The gun's own texture and color under the finish (shaders/weapon_finish.gdshader)
			var base = mi.get_active_material(i)
			var m = ShaderMaterial.new()
			m.shader = _finish_shader()
			if base is BaseMaterial3D:
				m.set_shader_parameter("albedo", base.albedo_color)
				if base.albedo_texture:
					m.set_shader_parameter("albedo_texture", base.albedo_texture)
			m.set_shader_parameter("tint", w.tint)
			m.set_shader_parameter("metal", w.metal)
			m.set_shader_parameter("rough", w.rough)
			m.set_shader_parameter("glow", Vector3(w.glow.r, w.glow.g, w.glow.b))
			m.set_shader_parameter("pattern", int(pat[0]))
			m.set_shader_parameter("pattern_scale", float(pat[1]))
			m.set_shader_parameter("pattern_color", pat[2])
			mi.set_surface_override_material(i, m)

static var _finish: Shader = null

static func _finish_shader() -> Shader:
	if not _finish:
		_finish = load("res://shaders/weapon_finish.gdshader")
	return _finish
