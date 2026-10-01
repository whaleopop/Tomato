## Ammo card (bottom-right): big magazine count, reserve and reload progress
extends GlassPanel
class_name AmmoDisplay

var combat_component: CombatComponent = null
var inventory_component: InventoryComponent = null

var weapon_label: Label = null
var ammo_label: Label = null
var magazine_label: Label = null
var reserve_label: Label = null
var reload_bar: ProgressBar = null

const RELOAD_COLOR = UITheme.ACCENT_WARNING
const LOW_AMMO_COLOR = UITheme.ACCENT_DANGER
const NORMAL_COLOR = Color.WHITE

func _init():
	super._init()
	padding = 16
	tint = UITheme.GLASS_TINT_HUD
	custom_minimum_size = Vector2(210, 0)

func _ready():
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	weapon_label = UITheme.create_caption("", box)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	ammo_label = Label.new()
	ammo_label.add_theme_font_override("font", UITheme.font_black())
	ammo_label.add_theme_font_size_override("font_size", 40)
	row.add_child(ammo_label)

	magazine_label = UITheme.create_label("", row, UITheme.FONT_HEADING)
	magazine_label.size_flags_vertical = Control.SIZE_SHRINK_END
	magazine_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

	reserve_label = UITheme.create_label("", box, UITheme.FONT_SMALL)

	reload_bar = UITheme.create_progress_bar(1.0, 0.0, RELOAD_COLOR, box)
	reload_bar.custom_minimum_size.y = 6
	reload_bar.visible = false

func setup(p_combat: CombatComponent, p_inventory: InventoryComponent = null):
	combat_component = p_combat
	inventory_component = p_inventory

	if combat_component:
		combat_component.reload_started.connect(_on_reload_started)
		combat_component.reload_finished.connect(_on_reload_finished)
		combat_component.weapon_changed.connect(_on_weapon_changed)

func _process(_delta: float):
	_update_display()

func _update_display():
	var weapon = combat_component.equipped_ranged_weapon if combat_component else null
	if not weapon:
		visible = false
		return
	visible = true

	weapon_label.text = tr(weapon.item_name).to_upper()
	ammo_label.text = str(weapon.current_ammo)
	magazine_label.text = "/ %d" % weapon.magazine_size

	var color = NORMAL_COLOR
	if combat_component.is_reloading:
		color = RELOAD_COLOR
	elif weapon.current_ammo <= weapon.magazine_size * 0.25:
		color = LOW_AMMO_COLOR
	ammo_label.add_theme_color_override("font_color", color)

	if combat_component.entity and combat_component.entity.has_meta("endless_ammo"):
		reserve_label.text = tr("Reserve  ∞")  # Weed Swarm
		reserve_label.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	elif inventory_component:
		var reserve = inventory_component.get_ammo_count(weapon.ammo_type)
		reserve_label.text = tr("Reserve  %d") % reserve if reserve > 0 else tr("No reserve ammo")
		reserve_label.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY if reserve > 0 else LOW_AMMO_COLOR)
	else:
		reserve_label.text = ""

	if combat_component.is_reloading and weapon.reload_time > 0:
		reload_bar.visible = true
		reload_bar.value = clamp(1.0 - (combat_component.reload_timer / weapon.reload_time), 0.0, 1.0)
	else:
		reload_bar.visible = false

func _on_reload_started():
	reload_bar.visible = true
	reload_bar.value = 0.0

func _on_reload_finished():
	reload_bar.visible = false
	var tween = create_tween()
	tween.tween_property(ammo_label, "modulate", Color(0.6, 1.4, 0.6), 0.12)
	tween.tween_property(ammo_label, "modulate", Color.WHITE, 0.2)

func _on_weapon_changed(_weapon):
	reload_bar.visible = false
	_update_display()
