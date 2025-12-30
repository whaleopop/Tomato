## Tests for inventory system
extends "res://addons/gut/test.gd"

var inventory: Inventory
var health_pack: HealthPack

func before_each():
	inventory = Inventory.new(10)
	health_pack = HealthPack.new()

func after_each():
	pass

func test_inventory_add_item():
	var slot = inventory.add_item(health_pack)
	assert_ge(slot, 0)
	assert_eq(inventory.get_item(slot), health_pack)

func test_inventory_remove_item():
	var slot = inventory.add_item(health_pack)
	var removed = inventory.remove_item(slot)
	assert_eq(removed, health_pack)
	assert_eq(inventory.get_item(slot), null)

func test_inventory_full():
	for i in range(10):
		var pack = HealthPack.new()
		inventory.add_item(pack)
	
	var extra_pack = HealthPack.new()
	var slot = inventory.add_item(extra_pack)
	assert_eq(slot, -1)  # Inventory full

func test_inventory_stackable_items():
	var pack1 = HealthPack.new()
	var pack2 = HealthPack.new()
	
	var slot1 = inventory.add_item(pack1)
	var slot2 = inventory.add_item(pack2)
	
	assert_eq(slot1, slot2)  # Should stack
	assert_eq(inventory.get_item_count(slot1), 2)

