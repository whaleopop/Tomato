## Inventory overlay (toggle with I), in the main menu's look: a navy card with a gold kicker (the
## hero) over the title, navy slots that light up gold under the mouse and when chosen, the gun in
## hand on a gold tint. Drag a slot onto another to move / swap it, or onto USE / DROP to use or
## drop it; every change is also sent to the server (PlayerInputHandler.send_ui_action).
extends Control
class_name InventoryMenu

var inventory_component: InventoryComponent = null
var slot_buttons: Array[Button] = []
var weapon_slot_buttons: Array[Button] = []
var slots_container: GridContainer = null
var weapon_slots_container: HBoxContainer = null
var panel: PanelContainer = null
var kicker_label: Label = null
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
	dim.color = Color(0.02, 0.03, 0.07, 0.55)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center = CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	panel = UITheme.navy_panel(center, 26)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	var titles = UITheme.create_screen_title("INVENTORY", " ", header)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kicker_label = titles.get_child(0) as Label
	title_label = titles.get_child(titles.get_child_count() - 1) as Label
	var key = UITheme.create_pill("I", UITheme.TEXT_SECONDARY, header)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var close_btn = UITheme.create_icon_chip("✕", header, Vector2(44, 44))
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(func(): visible = false)

	# Weapon hot-bar section
	_section("Weapons  (1–2)", vbox)
	weapon_slots_container = HBoxContainer.new()
	weapon_slots_container.add_theme_constant_override("separation", 10)
	vbox.add_child(weapon_slots_container)
	for i in range(InventoryComponent.MAX_WEAPON_SLOTS):
		var ws = _create_weapon_slot_button(i)
		weapon_slots_container.add_child(ws)
		weapon_slot_buttons.append(ws)

	_section("Items", vbox)
	slots_container = GridContainer.new()
	slots_container.columns = SLOTS_PER_ROW
	slots_container.add_theme_constant_override("h_separation", 10)
	slots_container.add_theme_constant_override("v_separation", 10)
	vbox.add_child(slots_container)

	# What is chosen, in a navy strip
	var strip = PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UITheme.navy_box(Color(0.03, 0.04, 0.08, 0.7), Color(1, 1, 1, 0.06), 10, 14, 8))
	strip.custom_minimum_size = Vector2(0, 48)
	vbox.add_child(strip)
	info_label = UITheme.create_label("Select an item", strip, UITheme.FONT_SMALL)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	vbox.add_child(actions)

	var use_btn = UITheme.create_primary_button("USE", actions, Vector2(0, 50))
	use_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_btn.pressed.connect(_on_use_pressed)
	use_btn.set_drag_forwarding(Callable(), _can_drop_action, _drop_action.bind("use"))

	var drop_btn = UITheme.create_danger_button("DROP", actions, Vector2(0, 50))
	drop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_btn.pressed.connect(_on_drop_pressed)
	drop_btn.set_drag_forwarding(Callable(), _can_drop_action, _drop_action.bind("drop"))

	var hint = UITheme.create_label("Drag a slot onto another to move it, onto USE or DROP to use or drop it", vbox, UITheme.FONT_TINY)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = SLOTS_PER_ROW * (SLOT_SIZE.x + 10) - 10
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

## A small gold uppercase section line (the main menu's kicker)
func _section(text: String, parent: Control) -> void:
	var l = UITheme.create_label(text, parent, 13)
	l.uppercase = true
	l.add_theme_font_override("font", UITheme.font_black())
	l.add_theme_color_override("font_color", UITheme.GOLD)

## The slot looks: "empty", "item" (rim in the item's color), "active" (the gun in hand: gold
## tint) or "selected" (gold rim and glow); every one turns gold under the mouse
func _style_slot(button: Button, state: String, color: Color = Color.WHITE) -> void:
	var normal: StyleBoxFlat
	match state:
		"empty":
			normal = UITheme.navy_box(Color(0.03, 0.04, 0.08, 0.55), Color(1, 1, 1, 0.06), 14, 6, 6)
		"active":
			normal = UITheme.navy_box(Color(0.20, 0.15, 0.03, 0.92), Color(UITheme.GOLD, 0.6), 14, 6, 6)
		"selected":
			normal = UITheme.navy_box(Color(0.16, 0.13, 0.05, 0.95), UITheme.GOLD, 14, 6, 6)
			normal.set_border_width_all(2)
			normal.shadow_color = Color(UITheme.GOLD, 0.45)
			normal.shadow_size = 12
		_:
			normal = UITheme.navy_box(UITheme.NAVY, Color(color, 0.35), 14, 6, 6)
	var hover = normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.08) if state != "empty" else Color(UITheme.NAVY_HOVER, 0.7)
	hover.border_color = Color(UITheme.GOLD, 0.9 if state != "empty" else 0.4)
	hover.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", UITheme.GOLD)

func setup(p_inventory_component: InventoryComponent):
	inventory_component = p_inventory_component

	if inventory_component:
		var hero = inventory_component.entity.character_data if inventory_component.entity and "character_data" in inventory_component.entity else null
		if hero and kicker_label:
			kicker_label.text = hero.character_name
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
	name_label.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_override("font", UITheme.font_black())
	if count > 1:
		var n = UITheme.create_label("×%d" % count, button, 12)
		n.add_theme_font_override("font", UITheme.font_black())
		n.add_theme_color_override("font_color", UITheme.GOLD)
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
		_style_slot(button, "selected" if index == selected_slot else "item", _item_color(slot.item))
	else:
		_style_slot(button, "selected" if index == selected_slot else "empty")

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
		info_label.text = tr(item_slot.item.item_name)
		if item_slot.item.description:
			info_label.text += "  ·  %s" % tr(item_slot.item.description)
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
			_style_slot(btn, "selected" if is_sel else ("active" if is_active else "item"), UITheme.ACCENT_SECONDARY)
			_add_icon(btn, weapon, "%d  %s" % [i + 1, tr(weapon.item_name, "short")])
		else:
			for c in btn.get_children():
				c.queue_free()
			_style_slot(btn, "selected" if is_sel else "empty")
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
	var preview = button.duplicate(0) as Button
	preview.modulate.a = 0.9
	preview.size = button.size
	_style_slot(preview, "selected")  # lifted: gold rim and glow, a little bigger and tilted
	preview.pivot_offset = button.size / 2.0
	preview.scale = Vector2(1.1, 1.1)
	preview.rotation = 0.07
	var holder = Control.new()  # the preview hangs centered on the cursor
	holder.add_child(preview)
	preview.position = -button.size / 2.0
	set_drag_preview(holder)
	button.modulate.a = 0.35  # the slot it left
	_fade_back_after_drag(button)
	return {"inv_kind": kind, "index": index}

## The slot left behind comes back once the drag is over (dropped anywhere or cancelled)
func _fade_back_after_drag(button: Button) -> void:
	await get_tree().process_frame
	while is_instance_valid(button) and is_inside_tree() and get_viewport().gui_is_dragging():
		await get_tree().process_frame
	if is_instance_valid(button):
		button.modulate.a = 1.0

## USE / DROP take any dragged slot
func _can_drop_action(_at: Vector2, data) -> bool:
	return data is Dictionary and data.has("inv_kind")

## A slot dropped on USE / DROP: choose it, then do what the button does
func _drop_action(_at: Vector2, data, action: String) -> void:
	var index = int(data.index)
	if data.inv_kind == "weapon":
		_on_weapon_slot_pressed(index)
	else:
		_on_slot_pressed(index)
	if action == "use":
		_on_use_pressed()
	else:
		_on_drop_pressed()

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
			if get_parent():
				get_parent().move_child(self, -1)  # over the HUD bits added after us
			_update_inventory()
	elif visible and event.is_action_pressed("pause"):
		visible = false
		get_viewport().set_input_as_handled()
