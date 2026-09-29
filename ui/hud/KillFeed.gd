## Kill feed (top right, under the minimap): "Killer [gun] Victim" for every elimination in the
## match, names in their heroes' colors; rows with you in them stand out. Fed by
## NetworkManager.player_killed (the server's ServerPlayer._on_died on every peer).
extends VBoxContainer
class_name KillFeed

const MAX_ROWS: int = 5
const ROW_LIFE: float = 7.0

var my_id: int = 0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 6)
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
	var fill = Color(0.05, 0.07, 0.12, 0.72)
	var rim = Color(1, 1, 1, 0.08)
	if mine:
		var c = UITheme.ACCENT_DANGER if victim_id == my_id else UITheme.ACCENT_PRIMARY
		fill = Color(c.darkened(0.6), 0.8)
		rim = Color(c, 0.7)
	row.add_theme_stylebox_override("panel", UITheme.glass_box(fill, rim, 10, 12, 5))
	add_child(row)
	move_child(row, 0)  # newest on top

	var line = HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)

	if killer_id != 0:
		_name(line, String(info.get("killer_name", "")), String(info.get("killer_hero", "")), killer_id == my_id)
		var gun = weapon_name(int(info.get("weapon", -1)))
		var mark = UITheme.create_label("%s  ›" % tr(gun, "short") if gun != "" else "›", line, UITheme.FONT_TINY)
		mark.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		var skull = UITheme.create_label("☠", line, UITheme.FONT_SMALL)
		skull.add_theme_color_override("font_color", UITheme.ACCENT_WARNING)
		skull.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name(line, String(info.get("victim_name", "")), String(info.get("victim_hero", "")), victim_id == my_id)
	if killer_id == 0:
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
