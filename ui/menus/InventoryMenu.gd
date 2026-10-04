## Inventory overlay (toggle with I)
extends Control
class_name InventoryMenu

var inventory_component: InventoryComponent = null
var slot_buttons: Array[Button] = []
var weapon_slot_buttons: Array[Button] = []
var slots_container: GridContainer = null
var weapon_slots_container: HBoxContainer = null
var panel: GlassPanel = null
var title_label: Label = null
var info_label: Label = null
var selected_slot: int = -1       # >=0: item slot; -100..-104: weapon slot (-(slot+100))


const SLOT_SIZE = Vector2(78, 78)
const SLOTS_PER_ROW = 5

func _ready():
	visible = false
	add_to_group("blocks_game_input")  # PlayerInputHandler ignores the game while we're open
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_create_ui()

func _create_ui():
	var dim = ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.5)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center = CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	panel = UITheme.create_panel(center, 26)
	panel.tint = UITheme.GLASS_TINT_DARK

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	panel.add_child(vbox)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	title_label = UITheme.create_title("INVENTORY", header)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.create_spacer(false, header).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.create_pill("I", UITheme.TEXT_SECONDARY, header).size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var close_btn = UITheme.create_button("✕", header, Vector2(44, 44))
	close_btn.pressed.connect(func(): visible = false)

	# Weapon hot-bar section
	UITheme.create_caption("Weapons  (1–2)", vbox)
	weapon_slots_container = HBoxContainer.new()
	weapon_slots_container.add_theme_constant_override("separation", 10)
	vbox.add_child(weapon_slots_container)
	for i in range(InventoryComponent.MAX_WEAPON_SLOTS):
		var ws = _create_weapon_slot_button(i)
		weapon_slots_container.add_child(ws)
		weapon_slot_buttons.append(ws)

	UITheme.create_separator(vbox)
	UITheme.create_caption("Items", vbox)

	slots_container = GridContainer.new()
	slots_container.columns = SLOTS_PER_ROW
	slots_container.add_theme_constant_override("h_separation", 10)
	slots_container.add_theme_constant_override("v_separation", 10)
	vbox.add_child(slots_container)

	info_label = UITheme.create_label("Select an item", vbox, UITheme.FONT_SMALL)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(0, 40)

	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	vbox.add_child(actions)

	var use_btn = UITheme.create_primary_button("USE", actions, Vector2(0, 48))
	use_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_btn.pressed.connect(_on_use_pressed)

	var drop_btn = UITheme.create_danger_button("DROP", actions, Vector2(0, 48))
	drop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_btn.pressed.connect(_on_drop_pressed)

func setup(p_inventory_component: InventoryComponent):
	inventory_component = p_inventory_component

	if inventory_component:
		inventory_component.inventory.inventory_changed.connect(_update_inventory)
		inventory_component.weapon_slot_changed.connect(func(_s): _update_weapon_slots())
		inventory_component.weapon_equipped.connect(func(_w, _s): _update_weapon_slots())
		_update_inventory()
		_update_weapon_slots()

func _update_inventory():
	for button in slot_buttons:
		button.queue_free()
	slot_buttons.clear()

	if not inventory_component:
		return

	var inventory = inventory_component.get_inventory()
	if not inventory:
		return

	for i in range(inventory.max_size):
		var button = _create_slot_button(inventory.slots[i], i)
		slots_container.add_child(button)
		slot_buttons.append(button)

func _item_color(item) -> Color:
	if item is RangedWeapon:
		return UITheme.ACCENT_SECONDARY
	if item is AmmoItem:
		return UITheme.ACCENT_INFO
	return UITheme.ACCENT_PRIMARY

## The item's own picture (ItemRenderer) in the slot, its name under it and the count in the corner;
## the name alone until the picture is there (perks have none)
func _add_icon(button: Button, it: ItemData, title: String, count: int = 1) -> void:
	for c in button.get_children():
		c.queue_free()
	button.text = ""
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 5
	box.offset_right = -5
	box.offset_top = 5
	box.offset_bottom = -3
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)
	var pic = TextureRect.new()
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pic)
	var name_label = UITheme.create_label(title, box, 10)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_override("font", UITheme.font_black())
	if count > 1:
		var n = UITheme.create_label("×%d" % count, button, 12)
		n.add_theme_font_override("font", UITheme.font_black())
		n.position = Vector2(SLOT_SIZE.x - 30, 3)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ItemRenderer.get_instance(get_tree()).icon_for(it, func(tex):
		if is_instance_valid(pic):
			pic.texture = tex)

func _create_slot_button(slot, index: int) -> Button:
	var button = Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 12)

	if slot.item:
		_add_icon(button, slot.item, tr(slot.item.item_name), slot.count)
		var color = _item_color(slot.item)
		button.add_theme_stylebox_override("normal", UITheme.glass_box(Color(color, 0.10), Color(color, 0.45), 16, 6, 6))
		button.add_theme_stylebox_override("hover", UITheme.glow_box(Color(color, 0.22), 0.3, 16, 10))
	else:
		button.add_theme_stylebox_override("normal", UITheme.glass_box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.07), 16, 6, 6))

	if index == selected_slot:
		button.add_theme_stylebox_override("normal", UITheme.glow_box(Color(UITheme.ACCENT_PRIMARY, 0.25), 0.4, 16, 10))

	button.pressed.connect(_on_slot_pressed.bind(index))
	button.set_drag_forwarding(_drag_from.bind("item", index, button), _can_drop.bind("item", index), _drop_on.bind("item", index))
	return button

func _on_slot_pressed(slot: int):
	selected_slot = slot

	if not inventory_component:
		return

	var inventory = inventory_component.get_inventory()
	if not inventory or slot >= inventory.slots.size():
		return

	var item_slot = inventory.slots[slot]
	if item_slot.item:
		info_label.text = item_slot.item.item_name
		if item_slot.item.description:
			info_label.text += "  ·  %s" % item_slot.item.description
	else:
		info_label.text = "Empty slot"
	_update_inventory()

func _create_weapon_slot_button(index: int) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = SLOT_SIZE
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 11)
	btn.clip_text = true
	btn.pressed.connect(_on_weapon_slot_pressed.bind(index))
	btn.set_drag_forwarding(_drag_from.bind("weapon", index, btn), _can_drop.bind("weapon", index), _drop_on.bind("weapon", index))
	return btn

func _update_weapon_slots() -> void:
	if not inventory_component:
		return
	for i in range(weapon_slot_buttons.size()):
		var btn = weapon_slot_buttons[i] as Button
		if not btn:
			continue
		var weapon = inventory_component.get_weapon_in_slot(i)
		var is_active = i == inventory_component.current_weapon_slot and weapon != null
		var is_sel = selected_slot == -(i + 100)
		if weapon:
			var color = UITheme.ACCENT_SECONDARY
			if is_active:
				btn.add_theme_stylebox_override("normal", UITheme.glow_box(Color(color, 0.28), 0.4, 16, 10))
			elif is_sel:
				btn.add_theme_stylebox_override("normal", UITheme.glow_box(Color(UITheme.ACCENT_PRIMARY, 0.28), 0.4, 16, 10))
			else:
				btn.add_theme_stylebox_override("normal", UITheme.glass_box(Color(color, 0.12), Color(color, 0.5), 16, 6, 6))
			_add_icon(btn, weapon, "%d  %s" % [i + 1, tr(weapon.item_name, "short")])
		else:
			for c in btn.get_children():
				c.queue_free()
			btn.add_theme_stylebox_override("normal", UITheme.glass_box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.07), 16, 6, 6))
			btn.text = str(i + 1)

func _on_weapon_slot_pressed(index: int) -> void:
	selected_slot = -(index + 100)
	var weapon = inventory_component.get_weapon_in_slot(index) if inventory_component else null
	if weapon:
		info_label.text = tr(weapon.item_name)
	else:
		info_label.text = tr("Empty weapon slot")
	_update_weapon_slots()
	_update_inventory()

# ---------------------------------------------------------------- drag and drop
# Grab a gun or a bag item with the mouse and drop it on another slot of its kind: guns swap
# slots (the HUD bar follows), items move / stack / swap. The server is told the same move.

func _drag_from(_at: Vector2, kind: String, index: int, button: Button):
	if not inventory_component:
		return null
	var thing = inventory_component.get_weapon_in_slot(index) if kind == "weapon" else inventory_component.get_inventory().slots[index].item
	if thing == null:
		return null
	var preview = button.duplicate(0) as Control
	preview.modulate.a = 0.75
	preview.size = button.size
	var holder = Control.new()  # the preview hangs centered on the cursor
	holder.add_child(preview)
	preview.position = -button.size / 2.0
	set_drag_preview(holder)
	return {"inv_kind": kind, "index": index}

func _can_drop(_at: Vector2, data, kind: String, index: int) -> bool:
	return data is Dictionary and data.get("inv_kind") == kind and int(data.get("index", -1)) != index

func _drop_on(_at: Vector2, data, kind: String, index: int) -> void:
	var from = int(data.index)
	if kind == "weapon":
		if inventory_component.swap_weapon_slots(from, index):
			_send_to_server({"swap_weapons": [from, index]})
			if selected_slot == -(from + 100):
				selected_slot = -(index + 100)
		_update_weapon_slots()
	else:
		if inventory_component.move_item(from, index):
			_send_to_server({"move_item": [from, index]})
			if selected_slot == from:
				selected_slot = index
		_update_inventory()

func _on_use_pressed():
	if selected_slot < -99:
		# Weapon slot selected — equip it
		var w_slot = -(selected_slot + 100)
		if inventory_component:
			inventory_component.switch_weapon_slot(w_slot)
			_update_weapon_slots()
		return
	if selected_slot >= 0 and inventory_component:
		# The server does it for real (else the next health sync undoes a heal); here for feedback
		_send_to_server({"use_item": selected_slot})
		inventory_component.use_item(selected_slot)
		_update_inventory()

func _on_drop_pressed():
	if selected_slot < -99:
		# Drop weapon from slot
		var w_slot = -(selected_slot + 100)
		if inventory_component:
			_send_to_server({"drop_weapon": w_slot})
			if inventory_component.drop_weapon(w_slot):
				info_label.text = tr("Weapon dropped")
			_update_weapon_slots()
		return
	if selected_slot >= 0 and inventory_component:
		var inventory = inventory_component.get_inventory()
		if inventory and selected_slot < inventory.slots.size():
			_send_to_server({"drop_item": selected_slot})
			if inventory_component.drop_item(selected_slot):
				info_label.text = tr("Item dropped")
			else:
				info_label.text = tr("This can't be dropped")
			_update_inventory()

func _send_to_server(action: Dictionary):
	var owner_entity = inventory_component.entity if inventory_component else null
	var handler = owner_entity.get_node_or_null("InputHandler") if owner_entity else null
	if handler and handler.has_method("send_ui_action"):
		handler.send_ui_action(action)

func _input(event: InputEvent):
	if event.is_action_pressed("inventory"):
		visible = not visible
		if visible:
			_update_inventory()
	elif visible and event.is_action_pressed("pause"):
		visible = false
		get_viewport().set_input_as_handled()
