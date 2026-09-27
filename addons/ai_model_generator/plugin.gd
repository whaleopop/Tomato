@tool
extends EditorPlugin

var dock: Control

func _enter_tree():
	dock = preload("res://addons/ai_model_generator/generator_dock.gd").new()
	dock.name = "AI Models"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

func _exit_tree():
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
