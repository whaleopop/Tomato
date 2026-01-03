## Inventory menu UI - styled programmatically
extends Control
class_name InventoryMenu

var inventory_component: InventoryComponent = null
var slot_buttons: Array[Button] = []
var slots_container: GridContainer = null
var panel: PanelContainer = null
var title_label: Label = null
var info_label: Label = null

const SLOT_SIZE = Vector2(70, 70)
const SLOTS_PER_ROW = 5

func _ready():
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()

func _create_ui():
	# Semi-transparent background
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	# Main panel
	panel = UITheme.create_panel()
	panel.custom_minimum_size = Vector2(420, 450)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	panel.add_child(vbox)

	# Header
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	title_label = UITheme.create_title("INVENTORY", header)

	UITheme.create_spacer(true, header)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(35, 35)
	close_btn.pressed.connect(func(): visible = false)
	header.add_child(close_btn)

	# Separator
	UITheme.create_separator(vbox)

	# Slots grid
	slots_container = GridContainer.new()
	slots_container.columns = SLOTS_PER_ROW
	slots_container.add_theme_constant_override("h_separation", 8)
	slots_container.add_theme_constant_override("v_separation", 8)
	vbox.add_child(slots_container)

	# Info label (selected item info)
	info_label = UITheme.create_label("", vbox)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.custom_minimum_size.y = 40

	# Actions
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 15)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(actions)

	var use_btn = UITheme.create_button("USE", actions, Vector2(100, 40))
	use_btn.pressed.connect(_on_use_pressed)

	var drop_btn = UITheme.create_danger_button("DROP", actions, Vector2(100, 40))
	drop_btn.pressed.connect(_on_drop_pressed)

func setup(p_inventory_component: InventoryComponent):
	inventory_component = p_inventory_component

	if inventory_component:
		inventory_component.inventory.inventory_changed.connect(_update_inventory)
		_update_inventory()

func _update_inventory():
	# Clear existing slots
	for button in slot_buttons:
		button.queue_free()
	slot_buttons.clear()

	if not inventory_component:
		return

	var inventory = inventory_component.get_inventory()
	if not inventory:
		return

	# Create slot buttons
	for i in range(inventory.max_size):
		var slot = inventory.slots[i]
		var button = _create_slot_button(slot, i)
		slots_container.add_child(button)
		slot_buttons.append(button)

func _create_slot_button(slot, index: int) -> Button:
	var button = Button.new()
	button.custom_minimum_size = SLOT_SIZE

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = UITheme.BG_MEDIUM
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.4)
	button.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.border_color = UITheme.ACCENT_PRIMARY
	button.add_theme_stylebox_override("hover", hover_style)

	if slot.item:
		# Item name (shortened)
		var name = slot.item.item_name
		if name.length() > 8:
			name = name.substr(0, 7) + ".."
		button.text = name

		if slot.count > 1:
			button.text += "\nx%d" % slot.count

		# Color based on item type
		if slot.item is RangedWeapon:
			style.border_color = Color(0.7, 0.5, 0.2)
		elif slot.item is AmmoItem:
			style.border_color = Color(0.6, 0.6, 0.3)
	else:
		button.text = ""
		style.bg_color = Color(0.1, 0.1, 0.12)

	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(_on_slot_pressed.bind(index))

	return button

var selected_slot: int = -1

func _on_slot_pressed(slot: int):
	selected_slot = slot

	if not inventory_component:
		return

	var inventory = inventory_component.get_inventory()
	if not inventory or slot >= inventory.slots.size():
		return

	var item_slot = inventory.slots[slot]
	if item_slot.item:
		info_label.text = "%s" % item_slot.item.item_name
		if item_slot.item.description:
			info_label.text += " - %s" % item_slot.item.description
	else:
		info_label.text = "Empty slot"

	# Update selection highlight
	for i in range(slot_buttons.size()):
		var btn = slot_buttons[i]
		var style = btn.get_theme_stylebox("normal") as StyleBoxFlat
		if style:
			if i == slot and inventory.slots[i].item:
				style.border_color = UITheme.ACCENT_SUCCESS
			else:
				style.border_color = Color(0.3, 0.3, 0.4)

func _on_use_pressed():
	if selected_slot >= 0 and inventory_component:
		inventory_component.use_item(selected_slot)
		_update_inventory()

func _on_drop_pressed():
	if selected_slot >= 0 and inventory_component:
		var inventory = inventory_component.get_inventory()
		if inventory and selected_slot < inventory.slots.size():
			inventory.remove_item(selected_slot)
			_update_inventory()
			info_label.text = "Item dropped"

func _input(event: InputEvent):
	if event.is_action_pressed("inventory"):
		visible = not visible
		if visible:
			_update_inventory()
