## Entry point for scenes/ProfileScene.tscn: a thin wrapper so MenuShell can say whose profile to
## open before the scene loads (open_account_id survives the scene swap; 0 = our own, set by
## ProfileView.account_id's own default). Read once and cleared.
extends Control
class_name ProfileScene

static var open_account_id: int = 0

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var view = ProfileView.new()
	view.account_id = open_account_id
	open_account_id = 0
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
