## Entry point for scenes/FriendsScene.tscn: hosts FriendsPanel full-screen.
extends Control
class_name FriendsScene

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel = FriendsPanel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
