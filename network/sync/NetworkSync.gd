## General network synchronization manager
extends Node
class_name NetworkSync

var sync_objects: Array[Node] = []

func _ready():
	pass

func register_sync_object(obj: Node):
	if not sync_objects.has(obj):
		sync_objects.append(obj)

func unregister_sync_object(obj: Node):
	var index = sync_objects.find(obj)
	if index >= 0:
		sync_objects.remove_at(index)

func sync_all():
	for obj in sync_objects:
		if is_instance_valid(obj):
			_sync_object(obj)

func _sync_object(obj: Node):
	# Override in subclasses
	pass
