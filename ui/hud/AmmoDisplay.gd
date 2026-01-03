## Displays current ammo count and reload status
extends Control
class_name AmmoDisplay

var combat_component: CombatComponent = null
var inventory_component: InventoryComponent = null

var ammo_label: Label = null
var reserve_label: Label = null
var reload_bar: ProgressBar = null
var weapon_icon: TextureRect = null
var container: HBoxContainer = null

const RELOAD_COLOR = Color(1, 0.8, 0.3)
const LOW_AMMO_COLOR = Color(1, 0.3, 0.3)
const NORMAL_COLOR = Color.WHITE

func _ready():
	_create_ui()

func _create_ui():
	# Main container
	container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 10)
	add_child(container)

	# Weapon icon placeholder
	weapon_icon = TextureRect.new()
	weapon_icon.custom_minimum_size = Vector2(48, 48)
	weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	container.add_child(weapon_icon)

	# Ammo info container
	var ammo_container = VBoxContainer.new()
	ammo_container.add_theme_constant_override("separation", 2)
	container.add_child(ammo_container)

	# Current ammo / magazine size
	ammo_label = Label.new()
	ammo_label.text = "12 / 12"
	ammo_label.add_theme_font_size_override("font_size", 24)
	ammo_label.add_theme_color_override("font_color", NORMAL_COLOR)
	ammo_container.add_child(ammo_label)

	# Reserve ammo
	reserve_label = Label.new()
	reserve_label.text = "Reserve: 60"
	reserve_label.add_theme_font_size_override("font_size", 14)
	reserve_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	ammo_container.add_child(reserve_label)

	# Reload progress bar (hidden by default)
	reload_bar = ProgressBar.new()
	reload_bar.custom_minimum_size = Vector2(100, 8)
	reload_bar.max_value = 1.0
	reload_bar.value = 0.0
	reload_bar.visible = false
	reload_bar.show_percentage = false
	ammo_container.add_child(reload_bar)

	# Style reload bar
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = RELOAD_COLOR
	bar_style.corner_radius_top_left = 4
	bar_style.corner_radius_top_right = 4
	bar_style.corner_radius_bottom_left = 4
	bar_style.corner_radius_bottom_right = 4
	reload_bar.add_theme_stylebox_override("fill", bar_style)

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
	if not combat_component:
		visible = false
		return

	var weapon = combat_component.equipped_ranged_weapon
	if not weapon:
		visible = false
		return

	visible = true

	# Update ammo count
	var current = weapon.current_ammo
	var magazine = weapon.magazine_size

	ammo_label.text = "%d / %d" % [current, magazine]

	# Color based on ammo state
	if combat_component.is_reloading:
		ammo_label.add_theme_color_override("font_color", RELOAD_COLOR)
	elif current <= magazine * 0.25:
		ammo_label.add_theme_color_override("font_color", LOW_AMMO_COLOR)
	else:
		ammo_label.add_theme_color_override("font_color", NORMAL_COLOR)

	# Update reserve ammo
	if inventory_component:
		var reserve = inventory_component.get_ammo_count(weapon.ammo_type)
		reserve_label.text = "Reserve: %d" % reserve
	else:
		reserve_label.text = ""

	# Update reload bar
	if combat_component.is_reloading:
		reload_bar.visible = true
		var progress = 1.0 - (combat_component.reload_timer / weapon.reload_time)
		reload_bar.value = clamp(progress, 0.0, 1.0)
	else:
		reload_bar.visible = false

func _on_reload_started():
	reload_bar.visible = true
	reload_bar.value = 0.0

	# Flash effect
	var tween = create_tween()
	tween.tween_property(ammo_label, "modulate", Color(1, 1, 0), 0.1)
	tween.tween_property(ammo_label, "modulate", Color.WHITE, 0.1)

func _on_reload_finished():
	reload_bar.visible = false

	# Success flash
	var tween = create_tween()
	tween.tween_property(ammo_label, "modulate", Color(0.3, 1, 0.3), 0.15)
	tween.tween_property(ammo_label, "modulate", Color.WHITE, 0.15)

func _on_weapon_changed(_weapon: WeaponData):
	# Reset display when weapon changes
	reload_bar.visible = false
	_update_display()
