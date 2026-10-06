## Weapons cluster (bottom-right): a strip of compact weapon slots above one quiet card with the
## active gun's picture, name, big magazine count, reserve and reload progress.
## `weapon_slots_ui` (the strip) is exposed for PlayerHUD / the trailer director.
extends VBoxContainer
class_name AmmoDisplay

const RELOAD_COLOR = UITheme.ACCENT_WARNING
const LOW_AMMO_COLOR = UITheme.ACCENT_DANGER
const NORMAL_COLOR = Color.WHITE
const SLOT_SIZE = Vector2(64, 40)
const PIC_SIZE = Vector2(120, 54)

var combat_component: CombatComponent = null
var inventory_component: InventoryComponent = null

var weapon_slots_ui: HBoxContainer = null
var card: PanelContainer = null
var weapon_pic: TextureRect = null
var weapon_label: Label = null
var ammo_label: Label = null
var magazine_label: Label = null
var reserve_label: Label = null
var reserve_icon: TextureRect = null
var reload_bar: ProgressBar = null

var _pic_weapon = null

func _init():
	custom_minimum_size = Vector2(420, 0)
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready():
	# --- slot strip
	weapon_slots_ui = HBoxContainer.new()
	weapon_slots_ui.name = "WeaponSlots"
	weapon_slots_ui.alignment = BoxContainer.ALIGNMENT_END
	weapon_slots_ui.add_theme_constant_override("separation", 6)
	weapon_slots_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(weapon_slots_ui)
	for i in range(InventoryComponent.MAX_WEAPON_SLOTS):
		weapon_slots_ui.add_child(_create_slot(i))

	# --- the card
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UITheme.glass_box(UITheme.GLASS_TINT_HUD, Color(1, 1, 1, 0.08), UITheme.CORNER_RADIUS_SMALL, 14, 10))
	add_child(card)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)

	weapon_pic = TextureRect.new()
	weapon_pic.custom_minimum_size = PIC_SIZE
	weapon_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	weapon_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	weapon_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(weapon_pic)

	var info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	weapon_label = UITheme.create_label("", info, UITheme.FONT_SMALL)
	weapon_label.uppercase = true
	weapon_label.clip_text = true
	weapon_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

	var mag_row = HBoxContainer.new()
	mag_row.add_theme_constant_override("separation", 6)
	mag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(mag_row)
	ammo_label = Label.new()
	ammo_label.add_theme_font_override("font", UITheme.font_black())
	ammo_label.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
	mag_row.add_child(ammo_label)
	magazine_label = UITheme.create_label("", mag_row, UITheme.FONT_HEADING)
	magazine_label.size_flags_vertical = Control.SIZE_SHRINK_END
	magazine_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

	var reserve_row = HBoxContainer.new()
	reserve_row.add_theme_constant_override("separation", 6)
	reserve_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(reserve_row)
	reserve_label = UITheme.create_label("", reserve_row, UITheme.FONT_SMALL)
	reserve_icon = UITheme.create_icon("infinity", reserve_row, UITheme.FONT_SMALL * 1.2, UITheme.TEXT_SECONDARY)
	reserve_icon.visible = false

	reload_bar = UITheme.create_progress_bar(1.0, 0.0, RELOAD_COLOR, col)
	reload_bar.custom_minimum_size.y = 4
	reload_bar.visible = false

func setup(p_combat: CombatComponent, p_inventory: InventoryComponent = null):
	combat_component = p_combat
	inventory_component = p_inventory

	if combat_component:
		if not combat_component.reload_started.is_connected(_on_reload_started):
			combat_component.reload_started.connect(_on_reload_started)
		if not combat_component.reload_finished.is_connected(_on_reload_finished):
			combat_component.reload_finished.connect(_on_reload_finished)
		if not combat_component.weapon_changed.is_connected(_on_weapon_changed):
			combat_component.weapon_changed.connect(_on_weapon_changed)
	if inventory_component:
		if not inventory_component.weapon_equipped.is_connected(_on_weapon_equipped):
			inventory_component.weapon_equipped.connect(_on_weapon_equipped)
		if not inventory_component.weapon_slot_changed.is_connected(_on_weapon_slot_changed):
			inventory_component.weapon_slot_changed.connect(_on_weapon_slot_changed)
		update_slots()

func _on_weapon_equipped(_w, _s) -> void:
	update_slots()

func _on_weapon_slot_changed(_s) -> void:
	update_slots()

func _process(_delta: float):
	_update_display()

# ---------------------------------------------------------------- slots

func _create_slot(index: int) -> PanelContainer:
	var slot = PanelContainer.new()
	slot.name = "WeaponSlot_%d" % (index + 1)
	slot.custom_minimum_size = SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_theme_stylebox_override("panel", _slot_box(false))

	var pic = TextureRect.new()
	pic.name = "WeaponPic"
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(pic)

	var chip = UITheme.create_label(str(index + 1), slot, UITheme.FONT_TINY)
	chip.name = "NumberLabel"
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	chip.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	return slot

func _slot_box(selected: bool) -> StyleBoxFlat:
	var box = UITheme.glass_box(UITheme.GLASS_TINT_HUD, Color(1, 1, 1, 0.08), 8, 4, 3)
	if selected:
		box.border_color = UITheme.GOLD
		box.set_border_width_all(2)
	return box

func update_slots():
	if inventory_component == null or weapon_slots_ui == null:
		return
	for i in range(InventoryComponent.MAX_WEAPON_SLOTS):
		var slot = weapon_slots_ui.get_node_or_null("WeaponSlot_%d" % (i + 1))
		if not slot:
			continue
		var weapon = inventory_component.get_weapon_in_slot(i)
		var selected = i == inventory_component.current_weapon_slot and weapon != null
		slot.add_theme_stylebox_override("panel", _slot_box(selected))
		slot.modulate.a = 1.0 if weapon else 0.4
		var chip = slot.get_node_or_null("NumberLabel") as Label
		if chip:
			chip.add_theme_color_override("font_color", UITheme.GOLD if selected else UITheme.TEXT_MUTED)
		var pic = slot.get_node_or_null("WeaponPic") as TextureRect
		if pic:
			_load_pic(pic, weapon)

## The gun's own picture (ItemRenderer, in its finish); cleared when the slot is empty
func _load_pic(pic: TextureRect, weapon) -> void:
	pic.set_meta("weapon", weapon)
	if weapon == null:
		pic.texture = null
		return
	ItemRenderer.get_instance(get_tree()).icon_for(weapon, func(tex):
		if is_instance_valid(pic) and pic.get_meta("weapon", null) == weapon:
			pic.texture = tex)

# ---------------------------------------------------------------- card

func _update_display():
	var weapon = combat_component.equipped_ranged_weapon if combat_component else null
	if not weapon:
		card.visible = false
		_pic_weapon = null
		return
	card.visible = true
	if weapon != _pic_weapon:
		_pic_weapon = weapon
		_load_pic(weapon_pic, weapon)

	weapon_label.text = weapon.item_name
	ammo_label.text = str(weapon.current_ammo)
	magazine_label.text = "/ %d" % weapon.magazine_size

	var color = NORMAL_COLOR
	if combat_component.is_reloading:
		color = RELOAD_COLOR
	elif weapon.current_ammo <= weapon.magazine_size * 0.25:
		color = LOW_AMMO_COLOR
	ammo_label.add_theme_color_override("font_color", color)

	if combat_component.entity and combat_component.entity.has_meta("endless_ammo"):
		reserve_label.text = tr("Reserve")  # Weed Swarm
		reserve_icon.visible = true
		reserve_label.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	elif inventory_component:
		reserve_icon.visible = false
		var reserve = inventory_component.get_ammo_count(weapon.ammo_type)
		reserve_label.text = tr("Reserve  %d") % reserve if reserve > 0 else tr("No reserve ammo")
		reserve_label.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY if reserve > 0 else LOW_AMMO_COLOR)
	else:
		reserve_icon.visible = false
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
