## Health packs and shields next to the ability bar: "[Q] + 2", "[E] shield 1" (the keys follow
## Keybinds), and while one is being used a progress bar above them with the seconds left.
extends Control
class_name ConsumableBar

const HEAL_COLOR = Color(0.45, 1.0, 0.5)
const SHIELD_COLOR = Color(0.45, 0.75, 1.0)

var inventory: InventoryComponent = null

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(p_inventory: InventoryComponent):
	inventory = p_inventory

func _process(_delta):
	queue_redraw()

func _draw():
	if not inventory:
		return
	var font = UITheme.font_black()
	var chip = Vector2(92, 40)
	var gap = 10.0
	var kinds = [["heal", "use_heal", HEAL_COLOR, "+"], ["shield", "use_shield", SHIELD_COLOR, "◆"]]
	var total_w = kinds.size() * chip.x + (kinds.size() - 1) * gap
	var x = (size.x - total_w) / 2.0
	var y = size.y - chip.y
	for k in kinds:
		var count = inventory.consumable_count(k[0])
		var active = inventory.using == k[0]
		var col: Color = k[2]
		var rect = Rect2(Vector2(x, y), chip)
		var fill = Color(0.05, 0.07, 0.12, 0.72)
		draw_style_box(UITheme.glass_box(fill, Color(col, 0.8 if active else (0.35 if count > 0 else 0.12)), 12, 0, 0), rect)
		var alpha = 1.0 if count > 0 else 0.35
		# key chip
		var key = Keybinds.label(k[1])
		var kw = font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var key_rect = Rect2(rect.position + Vector2(6, 8), Vector2(max(kw + 10, 24), 24))
		draw_style_box(UITheme.glass_box(Color(1, 1, 1, 0.12 * alpha), Color(1, 1, 1, 0.2 * alpha), 6, 0, 0), key_rect)
		draw_string(font, key_rect.position + Vector2((key_rect.size.x - kw) / 2.0, 17), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9 * alpha))
		# icon + count
		var tx = key_rect.end.x + 8
		draw_string(font, Vector2(tx, rect.position.y + 27), k[3], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(col, alpha))
		draw_string(font, Vector2(tx + 20, rect.position.y + 27), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, alpha))
		x += chip.x + gap

	# The one in progress: a bar over the chips with the time left
	if inventory.using != "":
		var col = HEAL_COLOR if inventory.using == "heal" else SHIELD_COLOR
		var bar = Rect2(Vector2((size.x - 240) / 2.0, y - 34), Vector2(240, 12))
		draw_style_box(UITheme.glass_box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.15), 6, 0, 0), bar)
		var p = clamp(inventory.use_progress(), 0.0, 1.0)
		if p > 0.0:
			draw_style_box(UITheme.glass_box(col, Color(1, 1, 1, 0.3), 6, 0, 0), Rect2(bar.position, Vector2(bar.size.x * p, bar.size.y)))
		var text = tr("Healing... %.1f s") % inventory.use_left if inventory.using == "heal" else tr("Shield... %.1f s") % inventory.use_left
		var tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string_outline(font, Vector2((size.x - tw) / 2.0, bar.position.y - 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.7))
		draw_string(font, Vector2((size.x - tw) / 2.0, bar.position.y - 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.lightened(0.3))
