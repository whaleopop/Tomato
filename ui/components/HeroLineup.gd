## The heroes standing in 3D (character select): every hero on a little hex pedestal in a circle,
## the chosen one in front on the glowing dais. Click a hero to choose it (the circle turns to bring
## it forward), hover one and it hops and shows its name; drag sideways to turn the circle (it
## snaps to the nearest hero), the wheel steps, a double click on the front hero spins it. Heroes
## you don't own stand dimmed under a lock with the price. Own World3D, transparent background
## (it sits over the scenic garden). Picking without physics: a box per hero against the mouse ray.
extends HiResView
class_name HeroLineup

signal hero_clicked(index: int)
signal hero_hovered(index: int)    # -1: none

const HERO_HEIGHT: float = 1.5      # the front hero, metres
const SIDE_SCALE: float = 0.62      # the others
const RADIUS_X: float = 4.4         # the circle, seen from the front: wide...
const RADIUS_Z: float = 2.9         # ...and not too deep
const DAIS_TOP: float = 0.24
const PEDESTAL_TOP: float = 0.14
const DRAG_PIXELS: float = 140.0    # mouse travel that turns the circle by one hero
const LOCK_SAT: float = 0.15        # locked heroes: saturation / brightness factors
const LOCK_VALUE: float = 0.42


var camera: Camera3D

var _roster: Array = []
var _locked: Array = []
var _wear_for: Callable = Callable()
var _slots: Array = []              # per hero: {root, pedestal, ring_mat, lift, bounce, holder, lock, box, glow, flash, hop}
var _rot: float = 0.0               # the circle's position: hero `_rot` stands in front
var _selected: int = 0
var _hovered: int = -1
var _turn: Tween = null
var _pressed: bool = false
var _dragging: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _press_rot: float = 0.0
var _time: float = 0.0
var _dais_mat: StandardMaterial3D
var _dais_light: OmniLight3D
var _chip: PanelContainer
var _chip_name: Label
var _chip_info: Label

func _init():
	super()
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE

	var env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.85)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 30, 0)
	key.light_energy = 1.35
	key.light_color = Color(1.0, 0.95, 0.86)
	key.shadow_enabled = true
	viewport.add_child(key)
	# Colored rims on the front hero, like the showcase's "neon glass" look
	for rim in [[Vector3(-1.9, 1.7, -1.0), Color(0.45, 1.0, 0.55), 2.2], [Vector3(1.9, 1.5, -0.9), Color(0.75, 0.45, 1.0), 2.0]]:
		var light = OmniLight3D.new()
		light.position = rim[0]
		light.light_color = rim[1]
		light.light_energy = rim[2]
		light.omni_range = 4.5
		viewport.add_child(light)
	_dais_light = OmniLight3D.new()      # the dais glows up at whoever stands on it
	_dais_light.position = Vector3(0, 0.45, 0.9)
	_dais_light.light_energy = 1.2
	_dais_light.omni_range = 2.6
	viewport.add_child(_dais_light)

	camera = Camera3D.new()
	camera.fov = 34.0
	camera.position = Vector3(0, 3.0, 6.9)
	viewport.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 1.25, -1.8))

	_build_dais()

func _ready():
	# The floating name over a hovered hero (2D, over the picture)
	_chip = PanelContainer.new()
	_chip.add_theme_stylebox_override("panel", UITheme.navy_box(Color(0.04, 0.055, 0.1, 0.94), Color(UITheme.GOLD, 0.8), 12, 14, 6))
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.visible = false
	add_child(_chip)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.add_child(row)
	_chip_name = UITheme.create_heading("", row)
	_chip_name.uppercase = true
	_chip_name.add_theme_font_override("font", UITheme.font_black())
	_chip_name.add_theme_font_size_override("font_size", 16)
	_chip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_info = UITheme.create_label("", row, UITheme.FONT_SMALL)
	_chip_info.add_theme_font_override("font", UITheme.font_bold())
	_chip_info.add_theme_color_override("font_color", UITheme.GOLD)
	_chip_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_exited.connect(func(): _set_hovered(-1))

## The big hex the chosen hero stands on: dark body, a ring in the hero's color, a gold rim below
func _build_dais():
	var dais = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.1
	cyl.height = DAIS_TOP
	cyl.radial_segments = 6
	dais.mesh = cyl
	var body = StandardMaterial3D.new()
	body.albedo_color = Color(0.12, 0.14, 0.22)
	body.roughness = 0.45
	body.metallic = 0.25
	dais.material_override = body
	dais.position.y = DAIS_TOP / 2.0
	viewport.add_child(dais)
	_dais_mat = _glow_material(UITheme.GOLD, 2.4)
	viewport.add_child(_hex_ring(0.98, 1.06, DAIS_TOP, _dais_mat))
	viewport.add_child(_hex_ring(1.08, 1.13, 0.03, _glow_material(UITheme.GOLD, 0.9)))

## roster: the heroes in order; locked[i]: dimmed with a lock (not owned); wear_for(name) ->
## {"skin": id, "hat": id} (PlayerProfile.equipped_for)
func show_heroes(roster: Array, locked: Array = [], wear_for: Callable = Callable()) -> void:
	for s in _slots:
		s.root.queue_free()
	_slots.clear()
	_roster = roster
	_locked = []
	for i in roster.size():
		_locked.append(i < locked.size() and bool(locked[i]))
	_wear_for = wear_for
	for i in roster.size():
		_slots.append(_make_slot(i))
		_load_model(i)
		_update_lock(i)
	_selected = clampi(_selected, 0, max(roster.size() - 1, 0))
	_rot = float(_selected)
	_set_hovered(-1)
	_color_dais(false)

## Bring hero `index` to the front dais
func select(index: int, animate: bool = true) -> void:
	var n = _slots.size()
	if n == 0:
		_selected = max(index, 0)
		return
	index = posmod(index, n)
	var changed = index != _selected
	_selected = index
	var target = _rot + _wrap(float(index) - _rot, n)
	if _turn and _turn.is_valid():
		_turn.kill()
	if animate and absf(target - _rot) > 0.001:
		_turn = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_turn.tween_property(self, "_rot", target, clampf(0.4 + absf(target - _rot) * 0.07, 0.4, 0.85))
	else:
		_rot = target
	_color_dais(animate)
	if changed and animate:
		_hop(index, 0.7)

## The skin / hat of one hero changed (bought, equipped): rebuild only that one
func refresh_hero(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	_load_model(index)
	_update_lock(index)

func set_locked(index: int, is_locked: bool) -> void:
	if index < 0 or index >= _slots.size() or _locked[index] == is_locked:
		return
	var was_locked: bool = _locked[index]
	_locked[index] = is_locked
	_apply_wear(index)
	if was_locked and not is_locked:
		# Unlocked: the lock pops, the ring flashes, the hero jumps for joy
		var s = _slots[index]
		s.flash = 7.0
		_hop(index, 1.3)
		var lock: Node3D = s.lock
		s.popping = true
		var t = create_tween()
		t.tween_property(lock, "scale", Vector3.ONE * 1.5, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(lock, "scale", Vector3.ONE * 0.01, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(func():
			s.popping = false
			_update_lock(index))
	else:
		_update_lock(index)

# ------------------------------------------------------------------ building

func _make_slot(i: int) -> Dictionary:
	var color: Color = _roster[i].color
	var root = Node3D.new()
	viewport.add_child(root)
	var pedestal = Node3D.new()           # hidden as its hero steps onto the big dais
	root.add_child(pedestal)
	var stone = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.46
	cyl.bottom_radius = 0.52
	cyl.height = PEDESTAL_TOP
	cyl.radial_segments = 6
	stone.mesh = cyl
	var body = StandardMaterial3D.new()
	body.albedo_color = Color(0.12, 0.14, 0.22)
	body.roughness = 0.5
	body.metallic = 0.2
	stone.material_override = body
	stone.position.y = PEDESTAL_TOP / 2.0
	pedestal.add_child(stone)
	var ring_mat = _glow_material(color, 1.2)
	pedestal.add_child(_hex_ring(0.45, 0.52, PEDESTAL_TOP, ring_mat))
	var lift = Node3D.new()               # the hero's height (pedestal / dais) and size
	root.add_child(lift)
	var bounce = Node3D.new()             # hops and squashes, pivot at the feet
	lift.add_child(bounce)
	var holder = Node3D.new()             # the model (spins on a double click)
	bounce.add_child(holder)
	var lock = _make_lock(i)
	lift.add_child(lock)
	return {"root": root, "pedestal": pedestal, "ring_mat": ring_mat, "lift": lift, "bounce": bounce,
		"holder": holder, "lock": lock, "box": AABB(Vector3(-0.4, 0, -0.4), Vector3(0.8, HERO_HEIGHT, 0.8)),
		"glow": 1.2, "flash": 0.0, "hop": null, "spin": null, "popping": false}

## A little gold padlock with the price, over a hero we don't own
func _make_lock(i: int) -> Node3D:
	var lock = Node3D.new()
	lock.position.y = HERO_HEIGHT + 0.42
	var gold = _glow_material(UITheme.GOLD, 0.8)
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	gold.metallic = 0.6
	gold.roughness = 0.35
	var body = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.3, 0.24, 0.1)
	body.mesh = box
	body.material_override = gold
	lock.add_child(body)
	var shackle = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.075
	torus.outer_radius = 0.11
	shackle.mesh = torus
	shackle.material_override = gold
	shackle.rotation_degrees.x = 90
	shackle.position.y = 0.13
	lock.add_child(shackle)
	var price = Label3D.new()
	price.name = "Price"
	price.text = tr("%d coins") % Cosmetics.price_of(Cosmetics.hero_id(_roster[i].character_name))
	price.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	price.font = UITheme.font_black()
	price.font_size = 48
	price.pixel_size = 0.0038
	price.outline_size = 14
	price.modulate = Color(1.0, 0.86, 0.45)
	price.outline_modulate = Color(0.03, 0.04, 0.08, 0.95)
	price.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	price.position.y = -0.3
	lock.add_child(price)
	return lock

func _load_model(i: int) -> void:
	var s = _slots[i]
	var holder: Node3D = s.holder
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	var data: CharacterData = _roster[i]
	var instance: Node3D = null
	if data.model_path != "" and ResourceLoader.exists(data.model_path):
		var scene = load(data.model_path)
		if scene:
			instance = scene.instantiate()
	if instance:
		ModelUtils.apply_lowpoly_look(instance)
	else:
		instance = MeshInstance3D.new()   # no model: a capsule in the hero's color
		var capsule = CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.2
		instance.mesh = capsule
		var mat = StandardMaterial3D.new()
		mat.albedo_color = data.color
		instance.material_override = mat
	holder.add_child(instance)
	var box = _normalize(instance)
	if box.size != Vector3.ZERO:
		s.box = AABB(box.position, box.size + Vector3(0, 0.2, 0))  # room for a hat
	_apply_wear(i)
	_play_idle(instance)

## The hero's skin and hat; locked heroes greyed and darkened on top (same shader uniforms)
func _apply_wear(i: int) -> void:
	var holder: Node3D = _slots[i].holder
	var wear = _wear(i)
	Cosmetics.apply_to_character(holder, String(wear.get("skin", "classic")), String(wear.get("hat", "")))
	if not _locked[i]:
		return
	var skin: Dictionary = Cosmetics.SKINS.get(String(wear.get("skin", "classic")), Cosmetics.SKINS.classic)
	var hsv: Vector3 = skin.hsv
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		if not mi.get_meta("cosmetic", false):
			mi.set_instance_shader_parameter("skin_hsv", Vector3(hsv.x, hsv.y * LOCK_SAT, hsv.z * LOCK_VALUE))
			mi.set_instance_shader_parameter("skin_tint", Color(0.36, 0.38, 0.46))
			mi.set_instance_shader_parameter("skin_glow", Color(0, 0, 0, 0))

func _wear(i: int) -> Dictionary:
	var hero: String = _roster[i].character_name
	if _wear_for.is_valid():
		var w = _wear_for.call(hero)
		if w is Dictionary:
			return w
	return PlayerProfile.equipped_for(hero)

func _update_lock(i: int) -> void:
	var lock: Node3D = _slots[i].lock
	lock.visible = _locked[i]
	lock.scale = Vector3.ONE

## Scale to HERO_HEIGHT, stand on y = 0, centered; returns the box it fills
func _normalize(instance: Node3D) -> AABB:
	instance.scale = Vector3.ONE
	instance.position = Vector3.ZERO
	var aabb = _collect_aabb(instance, Transform3D.IDENTITY)
	if aabb.size.y <= 0.0001:
		return AABB()
	var s = HERO_HEIGHT / max(aabb.size.y, max(aabb.size.x, aabb.size.z) * 0.8)  # wide ones (pumpkin)
	instance.scale = Vector3.ONE * s
	var center = aabb.get_center()
	instance.position = Vector3(-center.x * s, -aabb.position.y * s, -center.z * s)
	return AABB(Vector3(-aabb.size.x * s / 2.0, 0, -aabb.size.z * s / 2.0), aabb.size * s)

func _collect_aabb(node: Node, xform: Transform3D) -> AABB:
	var result = AABB()
	var has_any = false
	var node_xform = xform
	if node is Node3D:
		node_xform = xform * node.transform
	if node is MeshInstance3D and node.mesh:
		result = node_xform * node.get_aabb()
		has_any = true
	for child in node.get_children():
		var child_aabb = _collect_aabb(child, node_xform)
		if child_aabb.size != Vector3.ZERO:
			result = child_aabb if not has_any else result.merge(child_aabb)
			has_any = true
	return result

## Rigged heroes come with an idle clip; each starts at its own moment so they don't move as one
func _play_idle(instance: Node) -> void:
	var players = instance.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var ap: AnimationPlayer = players[0]
	if ap.has_animation("idle"):
		var clip = ap.get_animation("idle")
		clip.loop_mode = Animation.LOOP_LINEAR
		ap.play("idle")
		ap.seek(randf() * clip.length, true)

func _hex_ring(inner: float, outer: float, y: float, mat: Material) -> MeshInstance3D:
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 6
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = mat
	ring.position.y = y
	return ring

func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color.lightened(0.15)
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

# ------------------------------------------------------------------ every frame

## A position on the circle wrapped into [-n/2, n/2)
static func _wrap(value: float, n: int) -> float:
	return fposmod(value + n / 2.0, float(n)) - n / 2.0

func _process(delta: float):
	_time += delta
	var n = _slots.size()
	if n == 0:
		return
	for i in n:
		var s = _slots[i]
		var d = _wrap(float(i) - _rot, n)
		var a = d * TAU / n
		var front = clampf(1.0 - absf(d), 0.0, 1.0)
		front = front * front * (3.0 - 2.0 * front)
		var root: Node3D = s.root
		root.position = Vector3(sin(a) * RADIUS_X, 0, -(1.0 - cos(a)) * RADIUS_Z)
		# Everyone looks out towards the camera, the front one sways a little
		var to_cam = camera.position - root.position
		root.rotation.y = atan2(to_cam.x, to_cam.z) * 0.8 + sin(_time * 0.7 + i) * 0.12 * front
		var lift: Node3D = s.lift
		lift.scale = Vector3.ONE * lerpf(SIDE_SCALE, 1.0, front)
		lift.position.y = lerpf(PEDESTAL_TOP, DAIS_TOP, front)
		var pedestal: Node3D = s.pedestal
		pedestal.scale = Vector3(1.0, maxf(1.0 - front, 0.01), 1.0)
		pedestal.visible = front < 0.97
		# The ring: brighter under the mouse, dim when locked, flashes on unlock
		var target = (0.5 if _locked[i] else 1.3) + (2.8 if i == _hovered else 0.0)
		s.glow = lerpf(s.glow, target, 1.0 - exp(-delta * 10.0))
		s.flash = maxf(s.flash - delta * 9.0, 0.0)
		s.ring_mat.emission_energy_multiplier = s.glow + s.flash
		# Locked heroes stand as empty pedestals, not grey statues: only the one we're looking at
		# (front dais or under the mouse) shows its model, so you can see who you'd be buying
		var bounce: Node3D = s.bounce
		bounce.visible = not _locked[i] or front > 0.01 or i == _hovered or s.popping
		var lock: Node3D = s.lock
		lock.visible = (_locked[i] or s.popping) and (absf(d) < 2.5 or i == _hovered)  # the far side would be a wall of prices
		if lock.visible:
			lock.global_rotation = Vector3(0, 0, 0)   # faces the camera whatever the hero does
			# Floats over the head when the hero shows, hovers low over the empty pedestal otherwise
			var lock_height = (HERO_HEIGHT + 0.42) if bounce.visible else 0.55
			lock.position.y = lock_height + sin(_time * 2.2 + i) * 0.04
			if not s.popping:
				lock.scale = Vector3.ONE * lerpf(1.25, 0.7, front)  # readable at the sides, small in front
			# The price only on the front hero and the one under the mouse: next to each other
			# they ran into the neighbours
			var price = lock.get_node_or_null("Price")
			if price:
				price.visible = absf(d) < 0.5 or i == _hovered
	_place_chip()

func _place_chip() -> void:
	if not _chip or _hovered < 0 or _hovered >= _slots.size() or _dragging:
		if _chip:
			_chip.visible = false
		return
	var s = _slots[_hovered]
	var lift: Node3D = s.lift
	var head = lift.global_position + Vector3(0, (HERO_HEIGHT + (0.85 if _locked[_hovered] else 0.3)) * lift.scale.y, 0)
	if camera.is_position_behind(head):
		_chip.visible = false
		return
	var p = from_vp(camera.unproject_position(head))
	_chip.reset_size()
	var at = p - Vector2(_chip.size.x / 2.0, _chip.size.y)
	at.x = clampf(at.x, 4.0, maxf(size.x - _chip.size.x - 4.0, 4.0))
	at.y = clampf(at.y, 4.0, maxf(size.y - _chip.size.y - 4.0, 4.0))
	_chip.position = at
	_chip.visible = true

# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent):
	if _slots.is_empty():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed = true
				_dragging = false
				_press_pos = event.position
				_press_rot = _rot
				var hit = _pick(event.position)
				if event.double_click and hit == _selected:
					_spin(hit)
			elif _pressed:
				_pressed = false
				if _dragging:
					_dragging = false
					var index = posmod(roundi(_rot), _slots.size())
					select(index)
					hero_clicked.emit(index)
				else:
					var hit = _pick(event.position)
					if hit >= 0:
						Sfx.ui("ui_click")
						hero_clicked.emit(hit)
				_set_hovered(_pick(event.position))
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step = -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			hero_clicked.emit(posmod(_selected + step, _slots.size()))
			accept_event()
	elif event is InputEventMouseMotion:
		if _pressed and not _dragging and event.position.distance_to(_press_pos) > 6.0:
			_dragging = true
			if _turn and _turn.is_valid():
				_turn.kill()
			_press_rot = _rot + (event.position.x - _press_pos.x) / DRAG_PIXELS  # no jump when it starts
		if _dragging:
			# Turn with the mouse: dragging left brings the heroes on the right forward
			_rot = _press_rot - (event.position.x - _press_pos.x) / DRAG_PIXELS
			mouse_default_cursor_shape = Control.CURSOR_DRAG
			_set_hovered(-1)
		else:
			_set_hovered(_pick(event.position))
		accept_event()

## The hero under the mouse (nearest box the ray goes through), -1 for none
func _pick(at_local: Vector2) -> int:
	var at := to_vp(at_local)
	var from = camera.project_ray_origin(at)
	var dir = camera.project_ray_normal(at)
	var best = -1
	var best_distance = INF
	for i in _slots.size():
		var s = _slots[i]
		var holder: Node3D = s.holder
		var box: AABB = (holder.global_transform * s.box).grow(0.06)
		var hit = box.intersects_ray(from, dir)
		if hit != null:
			var distance = from.distance_to(hit)
			if distance < best_distance:
				best_distance = distance
				best = i
	return best

func _set_hovered(index: int) -> void:
	if not _dragging:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if index >= 0 else Control.CURSOR_ARROW
	if index == _hovered:
		return
	_hovered = index
	hero_hovered.emit(index)
	if index < 0:
		return
	_hop(index, 1.0)
	Sfx.ui("ui_hover")
	var hero: String = _roster[index].character_name
	_chip_name.text = tr(hero)
	if _locked[index]:
		_chip_info.text = tr("LOCKED") + "  ·  " + tr("%d coins") % Cosmetics.price_of(Cosmetics.hero_id(hero))
	else:
		_chip_info.text = tr("Lv %d") % int(PlayerProfile.hero_progress(hero).get("level", 1))
	var rim = Color(UITheme.TEXT_MUTED, 0.8) if _locked[index] else Color(UITheme.GOLD, 0.85)
	_chip.add_theme_stylebox_override("panel", UITheme.navy_box(Color(0.04, 0.055, 0.1, 0.94), rim, 12, 14, 6))

# ------------------------------------------------------------------ juice

## A hop with squash and stretch (the pivot is at the feet)
func _hop(i: int, strength: float = 1.0) -> void:
	if i < 0 or i >= _slots.size():
		return
	var s = _slots[i]
	var bounce: Node3D = s.bounce
	if s.hop and s.hop.is_valid():
		s.hop.kill()
	bounce.position.y = 0.0
	var t = create_tween()
	s.hop = t
	t.tween_property(bounce, "scale", Vector3(1.0 + 0.14 * strength, 1.0 - 0.18 * strength, 1.0 + 0.14 * strength), 0.07)
	t.tween_property(bounce, "scale", Vector3(1.0 - 0.08 * strength, 1.0 + 0.14 * strength, 1.0 - 0.08 * strength), 0.12)
	t.parallel().tween_property(bounce, "position:y", 0.3 * strength, 0.17).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(bounce, "scale", Vector3.ONE, 0.12)
	t.parallel().tween_property(bounce, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(bounce, "scale", Vector3(1.0 + 0.1 * strength, 1.0 - 0.12 * strength, 1.0 + 0.1 * strength), 0.06)
	t.tween_property(bounce, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A full turn on the spot (double click on the front hero)
func _spin(i: int) -> void:
	var s = _slots[i]
	var holder: Node3D = s.holder
	if s.spin and s.spin.is_valid():
		return
	holder.rotation.y = 0.0
	var t = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	s.spin = t
	t.tween_property(holder, "rotation:y", TAU, 0.8)
	t.tween_callback(func(): holder.rotation.y = 0.0)
	_hop(i, 0.8)

## The dais ring and its light take the front hero's color
func _color_dais(animate: bool) -> void:
	if _selected < 0 or _selected >= _roster.size():
		return
	var color: Color = _roster[_selected].color
	if _locked[_selected]:
		color = color.lerp(Color(0.6, 0.62, 0.7), 0.6)
	if animate:
		var t = create_tween().set_parallel(true)
		t.tween_property(_dais_mat, "albedo_color", color, 0.4)
		t.tween_property(_dais_mat, "emission", color.lightened(0.15), 0.4)
		t.tween_property(_dais_light, "light_color", color.lightened(0.3), 0.4)
	else:
		_dais_mat.albedo_color = color
		_dais_mat.emission = color.lightened(0.15)
		_dais_light.light_color = color.lightened(0.3)
