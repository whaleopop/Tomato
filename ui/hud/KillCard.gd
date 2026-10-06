extends Control
class_name KillCards
## The kill card: when WE kill someone, the victim pops up bottom-center as a hero card (their hero
## with crossed-out eyes, nickname, "Eliminated by you"), holds a moment and flies into the kills
## counter as a trophy. Fed by NetworkManager.player_killed only (the RPC info is fog-safe: the
## victim's name, hero and look come with it). One card at a time, the rest wait in a queue.
## Wiring: add as a full-rect child of the HUD, set player / kills_anchor / lane_bottom.
## Not in blocks_game_input (mouse ignored).

const APPEAR: float = 0.18
const HOLD: float = 1.5
const HOLD_QUEUED: float = 0.6
const FLY: float = 0.45
const X_COLOR = Color(0.055, 0.075, 0.13, 1.0)  # dark navy strokes (UITheme.NAVY without the alpha)
const CARD_SIZE = Vector2(150, 208)

## Eye centres in pixels of the 384 ItemRenderer hero snapshot (heroes look a little to the side, so
## the pair is asymmetric): [left in the picture, right, radius of the white]
const EYES = {
	"Tomato": [Vector2(146, 207), Vector2(203, 204), 23.0],
	"Grape": [Vector2(154, 210), Vector2(203, 206), 17.0],
	"Lemon": [Vector2(154, 202), Vector2(202, 202), 18.5],
	"Apple": [Vector2(151, 208), Vector2(201, 206), 19.0],
	"Watermelon": [Vector2(151, 207), Vector2(206, 205), 20.0],
	"Pineapple": [Vector2(162, 210), Vector2(199, 210), 16.5],
	"Banana": [Vector2(170, 199), Vector2(209, 195), 18.0],
	"Pumpkin": [Vector2(146, 204), Vector2(198, 204), 21.5],
	"Corn": [Vector2(160, 200), Vector2(200, 200), 17.5],
	"Beet": [Vector2(156, 222), Vector2(197, 222), 17.0],
	"Broccoli": [Vector2(159, 219), Vector2(204, 218), 18.5],
	"Pepper": [Vector2(154, 199), Vector2(203, 200), 20.0],
	"Carrot": [Vector2(160, 214), Vector2(197, 213), 17.0],
}
const EYES_FALLBACK = [Vector2(165, 140), Vector2(215, 140), 14.0]

static var _cache: Dictionary = {}   # "hero|skin|hat" -> ImageTexture
static var _stamp: Image = null

var player = null                    # the local Player (entity_id = whose kills count)
var lane_bottom: float = 150.0       # card bottom, px above the screen bottom
var kills_anchor: Control = null     # the kills counter (skull in the stats pill): the trophy flies there
var on_arrive: Callable = Callable() # called when a card lands in the counter
var trophies: Array = []             # [{name, hero}] of the cards that landed

var _queue: Array = []
var _busy: bool = false
var _pump_id: int = 0
var _showing: bool = false

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.has_signal("player_killed"):
		nm.player_killed.connect(_on_player_killed)

func _on_player_killed(victim_id: int, killer_id: int, info: Dictionary) -> void:
	if player == null or not is_instance_valid(player):
		return
	if killer_id == 0 or victim_id == killer_id or killer_id != int(player.entity_id):
		return
	var hero = String(info.get("victim_hero", ""))
	if hero == "" or CharacterRegistry.get_by_name(hero) == null:
		return
	var wear: Dictionary = info.get("victim_wear", {})
	_queue.append({
		"name": String(info.get("victim_name", "")),
		"hero": hero,
		"skin": String(wear.get("skin", "")),
		"hat": String(wear.get("hat", "")),
		"wear": wear,
	})
	_pump()

func _pump() -> void:
	if _busy or _queue.is_empty() or not is_inside_tree():
		return
	_busy = true
	_pump_id += 1
	var my_id := _pump_id
	var item: Dictionary = _queue.pop_front()
	# the renderer's callback may never come: give up on this card after 2 s
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(self) and _busy and my_id == _pump_id and not _showing:
			_busy = false
			_pump())
	ItemRenderer.get_instance(get_tree()).hero(item.hero, item.skin, item.hat, func(tex):
		if not is_instance_valid(self) or my_id != _pump_id:
			return
		_showing = true
		_show(item, crossed(tex, item.hero, item.skin, item.hat)))

func _show(item: Dictionary, art: Texture2D) -> void:
	var hero: CharacterData = CharacterRegistry.get_by_name(item.hero)
	var holder = VBoxContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_constant_override("separation", 8)
	holder.modulate.a = 0.0
	# The caption chip above the card
	var chip = PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", UITheme.glass_box(UITheme.GLASS_TINT_HUD, Color(UITheme.ACCENT_DANGER, 0.7), 99, 14, 5))
	UITheme.create_icon_label("skull", tr("Eliminated by you"), chip, UITheme.FONT_SMALL, UITheme.ACCENT_DANGER.lightened(0.35))
	holder.add_child(chip)
	var card = ParallaxCard.new()
	card.card_size = CARD_SIZE
	card.title = item.name
	card.subtitle = hero.character_name
	card.accent = hero.color
	card.art = art
	card.live = []  # a live model would bring the normal eyes back
	card.show_wear_mastery(item.wear)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.add_child(card)
	add_child(holder)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await get_tree().process_frame  # the box lays itself out
	if not is_instance_valid(holder):
		_showing = false
		_busy = false
		_pump()
		return
	holder.size = holder.get_combined_minimum_size()
	holder.pivot_offset = holder.size * 0.5
	holder.scale = Vector2.ONE * 0.6
	holder.position = Vector2((size.x - holder.size.x) * 0.5, size.y - lane_bottom - holder.size.y)
	var target = holder.position
	if kills_anchor and is_instance_valid(kills_anchor):
		target = kills_anchor.get_global_rect().get_center() - global_position - holder.size * 0.5
	var hold = HOLD_QUEUED if not _queue.is_empty() else HOLD
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(holder, "scale", Vector2.ONE, APPEAR).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(holder, "modulate:a", 1.0, APPEAR)
	t.chain().tween_interval(hold)
	t.chain().tween_property(holder, "position", target, FLY).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(holder, "scale", Vector2.ONE * 0.15, FLY).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(holder, "modulate:a", 0.5, FLY)
	t.chain().tween_callback(func():
		if is_instance_valid(holder):
			holder.queue_free()
		trophies.append({"name": item.name, "hero": item.hero})
		if on_arrive.is_valid():
			on_arrive.call()
		_showing = false
		_busy = false
		_pump())

# ---------------------------------------------------------------- crossed eyes

## The hero snapshot with the eyes painted over by a closed lid and an X on each
static func crossed(tex: Texture2D, hero: String, skin: String = "", hat: String = "") -> Texture2D:
	if tex == null:
		return null
	var key = "%s|%s|%s" % [hero, skin, hat]
	if _cache.has(key):
		return _cache[key]
	var img: Image = tex.get_image().duplicate()  # the renderer's cache stays untouched
	img.convert(Image.FORMAT_RGBA8)
	var eyes: Array = EYES.get(hero, EYES_FALLBACK)
	var r: float = eyes[2]
	for i in 2:
		var c: Vector2 = eyes[i]
		_lid(img, c, r)
	var stamp = _x_stamp()
	var side = int(round(r * 2.0))
	var scaled: Image = stamp.duplicate()
	scaled.resize(side, side, Image.INTERPOLATE_LANCZOS)
	for i in 2:
		var c: Vector2 = eyes[i]
		img.blend_rect(scaled, Rect2i(0, 0, side, side), Vector2i(int(round(c.x)) - side / 2, int(round(c.y)) - side / 2))
	var out = ImageTexture.create_from_image(img)
	_cache[key] = out
	return out

## A disc in the skin colour found around the eye (a closed lid)
static func _lid(img: Image, c: Vector2, r: float) -> void:
	var w = img.get_width()
	var h = img.get_height()
	var sum = Color(0, 0, 0, 0)
	var n = 0
	for off in [Vector2(0, 1.6), Vector2(1.6 * signf(c.x - 192.0), 0.2), Vector2(0, 1.9)]:
		var p = c + off * r
		var px = clampi(int(p.x), 0, w - 1)
		var py = clampi(int(p.y), 0, h - 1)
		var col = img.get_pixel(px, py)
		if col.a > 0.9:
			sum += col
			n += 1
	if n == 0:
		return
	var fill = Color(sum.r / n, sum.g / n, sum.b / n, 1.0)
	for y in range(maxi(0, int(c.y - r - 2)), mini(h, int(c.y + r + 3))):
		for x in range(maxi(0, int(c.x - r - 2)), mini(w, int(c.x + r + 3))):
			var cover = clampf(r + 0.5 - Vector2(x + 0.5, y + 0.5).distance_to(c), 0.0, 1.0)
			if cover <= 0.0:
				continue
			var old = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(old.r, old.g, old.b, 1.0).lerp(fill, cover) if old.a > 0.5 else old)

## The X, built once: two thick round-capped strokes, antialiased through the distance to the segment
static func _x_stamp() -> Image:
	if _stamp:
		return _stamp
	var n = 64
	var img = Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var half = 5.5
	var a1 = Vector2(13, 13)
	var b1 = Vector2(51, 51)
	var a2 = Vector2(51, 13)
	var b2 = Vector2(13, 51)
	for y in n:
		for x in n:
			var p = Vector2(x + 0.5, y + 0.5)
			var d = minf(_seg_dist(p, a1, b1), _seg_dist(p, a2, b2))
			var a = clampf(half + 0.5 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(X_COLOR, a))
	_stamp = img
	return img

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	var t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)
