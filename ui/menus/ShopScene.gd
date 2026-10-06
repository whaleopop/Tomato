## Entry point for scenes/ShopScene.tscn: a thin wrapper so MenuShell can set which tab / hero /
## gun to open on before the scene loads (static vars survive the scene swap, Shop.gd itself does
## not exist until _ready). Read once and cleared, so a later MenuShell.goto(SHOP) without setting
## them starts on the heroes tab again, not stuck on the last request.
extends Control
class_name ShopScene

static var open_kind: String = "hero"
static var open_hero: String = ""
static var open_weapon: int = -1

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shop = Shop.new()
	shop.start_kind = open_kind
	shop.start_hero = open_hero
	shop.start_weapon = open_weapon
	open_kind = "hero"
	open_hero = ""
	open_weapon = -1
	shop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shop)
