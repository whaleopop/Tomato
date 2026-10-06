## Kill feed (top right, under the minimap): "Killer [gun] Victim" for every elimination in the
## match, names in their heroes' colors; quiet rows (thin dark backing), rows with you in them
## get a gold bar on the left. Fed by NetworkManager.player_killed (the server's
## ServerPlayer._on_died on every peer).
extends VBoxContainer
class_name KillFeed

const MAX_ROWS: int = 5
const ROW_LIFE: float = 4.5

var my_id: int = 0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 3)
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.has_signal("player_killed"):
		network_manager.player_killed.connect(add_kill)

static func hero_color(hero_name: String) -> Color:
	var data = CharacterRegistry.get_by_name(hero_name) if hero_name != "" else null
	return data.color.lightened(0.35) if data else Color(0.9, 0.9, 0.95)

static func weapon_name(weapon_type: int) -> String:
	if weapon_type < 0:
		return ""
	var gun = RangedWeapon.create_weapon(weapon_type)
	return gun.item_name if gun else ""

func add_kill(victim_id: int, killer_id: int, info: Dictionary):
	var mine = my_id != 0 and (victim_id == my_id or killer_id == my_id)
	var row = PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	var back = StyleBoxFlat.new()
	back.bg_color = Color(UITheme.GLASS_TINT_HUD, 0.38)
	back.set_corner_radius_all(UITheme.CORNER_RADIUS_SMALL)
	back.content_margin_left = 10
	back.content_margin_right = 8
	back.content_margin_top = 3
	back.content_margin_bottom = 3
	if mine:  # gold bar on the left
		back.border_width_left = 3
		back.border_color = UITheme.GOLD
		back.corner_radius_top_left = 2
		back.corner_radius_bottom_left = 2
	row.add_theme_stylebox_override("panel", back)
	add_child(row)
	move_child(row, 0)  # newest on top

	var line = HBoxContainer.new()
	line.add_theme_constant_override("separation", 7)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)

	if killer_id != 0:
		_name(line, String(info.get("killer_name", "")), String(info.get("killer_hero", "")), killer_id == my_id)
		var gun = weapon_name(int(info.get("weapon", -1)))
		var mark = UITheme.create_icon("burst", line, UITheme.FONT_SMALL, Color(1, 1, 1, 0.65))
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if gun != "":
			mark.tooltip_text = tr(gun)
	elif info.has("npc"):
		# A weed got them
		var weed = String(info["npc"])
		var wl = UITheme.create_label(weed, line, UITheme.FONT_SMALL)
		wl.add_theme_font_override("font", UITheme.font_black())
		wl.add_theme_color_override("font_color", Weed.KINDS.get(weed, {}).get("color", Color.WHITE).lightened(0.2))
		wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var arrow = UITheme.create_icon("burst", line, UITheme.FONT_SMALL, Color(1, 1, 1, 0.65))
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		var skull = UITheme.create_icon("skull", line, UITheme.FONT_SMALL, UITheme.ACCENT_WARNING)
		skull.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name(line, String(info.get("victim_name", "")), String(info.get("victim_hero", "")), victim_id == my_id)
	if killer_id == 0 and not info.has("npc"):
		var how = UITheme.create_label("fell to the island", line, UITheme.FONT_TINY)
		how.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		how.mouse_filter = Control.MOUSE_FILTER_IGNORE

	while get_child_count() > MAX_ROWS:
		var last = get_child(get_child_count() - 1)
		remove_child(last)
		last.queue_free()

	row.modulate.a = 0.0
	var t = row.create_tween()
	t.tween_property(row, "modulate:a", 1.0, 0.2)
	t.tween_interval(ROW_LIFE)
	t.tween_property(row, "modulate:a", 0.0, 0.8)
	t.tween_callback(row.queue_free)

func _name(parent: Control, player_name: String, hero: String, is_me: bool):
	var label = UITheme.create_label(tr("You") if is_me else player_name, parent, UITheme.FONT_SMALL)
	label.add_theme_font_override("font", UITheme.font_black())
	label.add_theme_color_override("font_color", hero_color(hero))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var w = UITheme.font_black().get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL).x
	label.custom_minimum_size.x = min(ceil(w) + 2.0, 150.0)
