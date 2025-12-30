## Inventory menu UI
extends Control
class_name InventoryMenu

var inventory_component: InventoryComponent = null
var slot_buttons: Array[Button] = []

func _ready():
	visible = false

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
		var button = Button.new()
		button.custom_minimum_size = Vector2(60, 60)
		button.position = Vector2((i % 5) * 70, (i / 5) * 70)
		
		if slot.item:
			button.text = slot.item.item_name
			if slot.count > 1:
				button.text += " x%d" % slot.count
		
		button.pressed.connect(_on_slot_pressed.bind(i))
		add_child(button)
		slot_buttons.append(button)

func _on_slot_pressed(slot: int):
	if inventory_component:
		inventory_component.use_item(slot)

func _input(event: InputEvent):
	if event.is_action_pressed("inventory"):
		visible = not visible
