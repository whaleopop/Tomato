## Autoload: the persistent top bar of the menu screens (main menu, shop, profile, friends,
## settings). One ScreenHeader lives here, above every scene change (CanvasLayer layer 90, under
## SceneTransition's fade at 100): switching MAIN / SHOP / PROFILE / FRIENDS does not rebuild it,
## so the bar reads as one fixed piece of the game's chrome, not a popup. Each menu scene is its
## own .tscn (res://scenes/MainMenuScene.tscn, ShopScene.tscn, ProfileScene.tscn, FriendsScene.tscn)
## and calls MenuShell.goto(SceneId) from a tab or a back chip instead of touching SceneTransition
## directly, so the bar's active tab and settings chip always match what's on screen.
## Lobby / match scenes (character select, spawn select, matchmaking, the game) are not part of
## this bar: MenuShell.hide_bar() takes it off screen before fading there, show_bar() brings it
## back when the main menu loads. GameSceneController / CharacterSelect etc. need no change for
## that - MainMenuScene._ready calls show_bar(), everyone else just doesn't.
extends CanvasLayer

enum SceneId { MAIN, SHOP, PROFILE, FRIENDS, SETTINGS }

const PATHS = {
	SceneId.MAIN: "res://scenes/MainMenuScene.tscn",
	SceneId.SHOP: "res://scenes/ShopScene.tscn",
	SceneId.PROFILE: "res://scenes/ProfileScene.tscn",
	SceneId.FRIENDS: "res://scenes/FriendsScene.tscn",
}
## Tabs shown in the bar, in order: [SceneId, label key]. SETTINGS has no tab (it's the gear chip).
const TABS = [
	[SceneId.MAIN, "HOME"],
	[SceneId.SHOP, "SHOP"],
	[SceneId.PROFILE, "PROFILE"],
	[SceneId.FRIENDS, "FRIENDS"],
]

const TAB_FADE := 0.15
const BAR_LAYER := 90
const BAR_LAYER_FADING := 101  # above SceneTransition's fade (100) while switching tabs: the bar never blinks

var header: ScreenHeader = null
var _covers: Array[Node] = []   # overlays with their own header that hide the bar (cover())
var current: int = SceneId.MAIN
var _settings_layer: Control = null
var _root: Control = null  # a full-rect Control to host the header (ScreenHeader.make wants one; this CanvasLayer isn't)

func _ready():
	layer = BAR_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

## Builds the bar the first time a menu scene needs it (lazy: nothing to show before the main
## menu's own onboarding / update checks are done; show_bar() is the usual call)
func _ensure_header() -> void:
	if header and is_instance_valid(header):
		return
	if not _root or not is_instance_valid(_root):
		_root = Control.new()
		_root.name = "Root"
		_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_root)
	# No title zone: the bar is identical on every tab, nothing in it changes width.
	header = ScreenHeader.make(_root, "", "", false, false)
	for t in TABS:
		var id = t[0]
		header.add_tab(t[1], func(): goto(id))  # raw key: auto-translate follows the language
	header.add_icon_chip(UITheme.icon_texture("settings"), _open_settings, "Settings")
	_mark_active()

func show_bar() -> void:
	_ensure_header()
	header.visible = true

func hide_bar() -> void:
	if header and is_instance_valid(header):
		header.visible = false

## An overlay / scene with its own ScreenHeader: the bar steps aside while `node` lives.
func cover(node: Node) -> void:
	if not node or not is_instance_valid(node):
		return
	hide_bar()
	_covers.append(node)
	node.tree_exiting.connect(func():
		_covers.erase(node)
		_covers = _covers.filter(func(n): return is_instance_valid(n))
		if _covers.is_empty():
			show_bar(), CONNECT_ONE_SHOT)

## Q / E step through the tabs (wraps)
func _unhandled_input(event: InputEvent) -> void:
	if not header or not is_instance_valid(header) or not header.visible:
		return
	if _settings_layer and is_instance_valid(_settings_layer):
		return
	var tr_node = Engine.get_main_loop().root.get_node_or_null("/root/SceneTransition")
	if tr_node and tr_node.is_transitioning:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var step := 0
	if event.physical_keycode == KEY_Q:
		step = -1
	elif event.physical_keycode == KEY_E:
		step = 1
	if step == 0:
		return
	var idx := -1
	for i in TABS.size():
		if TABS[i][0] == current:
			idx = i
	if idx < 0:
		idx = 0 if step > 0 else TABS.size() - 1
	else:
		idx = posmod(idx + step, TABS.size())
	get_viewport().set_input_as_handled()
	goto(TABS[idx][0])

## Switch the current menu screen (a tab, a back chip, or a click in the 3D scene). Fades like
## any other scene change; the bar itself does not move.
func goto(id: int) -> void:
	if id == current and get_tree().current_scene and get_tree().current_scene.scene_file_path == PATHS.get(id, ""):
		return
	current = id
	_mark_active()
	var transition = Engine.get_main_loop().root.get_node_or_null("/root/SceneTransition")
	var path = PATHS.get(id, PATHS[SceneId.MAIN])
	if transition:
		layer = BAR_LAYER_FADING
		if not transition.transition_finished.is_connected(_restore_layer):
			transition.transition_finished.connect(_restore_layer, CONNECT_ONE_SHOT)
		transition.fade_to_scene(path, TAB_FADE)
	else:
		get_tree().change_scene_to_file(path)

func _restore_layer() -> void:
	await get_tree().process_frame
	var transition = Engine.get_main_loop().root.get_node_or_null("/root/SceneTransition")
	if transition and transition.is_transitioning:
		transition.transition_finished.connect(_restore_layer, CONNECT_ONE_SHOT)  # a queued fade started
		return
	layer = BAR_LAYER

func _mark_active() -> void:
	if not header:
		return
	for i in TABS.size():
		if TABS[i][0] == current:
			header.set_active_tab(i)
			return
	header.set_active_tab(-1)  # FRIENDS / SETTINGS: no tab lights up

func _open_settings() -> void:
	if _settings_layer and is_instance_valid(_settings_layer):
		return
	var transition = Engine.get_main_loop().root.get_node_or_null("/root/SceneTransition")
	if transition and transition.is_transitioning:
		return
	_ensure_header()
	_settings_layer =ScreenHeader.open_settings(_root, true)
	_settings_layer.tree_exited.connect(func(): _settings_layer = null)
