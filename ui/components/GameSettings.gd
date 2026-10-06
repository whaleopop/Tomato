## Persistent player settings (user://settings.cfg)
extends RefCounted
class_name GameSettings

const PATH = "user://settings.cfg"
## 2: VSync became off by default. Older files always stored vsync=true (every save wrote the
## old default), so on migration it is switched off once.
const VERSION = 2

static var master_volume: float = 0.8
static var sfx_volume: float = 0.8      # guns, blasts, loot... (bus "SFX", effects/Sfx.gd)
static var ui_volume: float = 0.7       # menus, countdown, results (bus "UI")
static var ambient_volume: float = 0.7  # wind, water, birds (bus "Ambient", AmbientSound)
static var fullscreen: bool = false
static var vsync: bool = false
static var language: String = "ru"
static var player_name: String = ""
static var last_server_ip: String = "127.0.0.1"
static var last_server_port: int = 7777
static var third_person: bool = false  # CameraController's view (V)
static var ui_scale: float = 1.0  # UIScale preset
static var juice_splatter: bool = true  # juice sprays, stains and footprints on hits (JuiceSplatter)
static var camera_locked: bool = true # top-down view turns with the hero (CameraController.locked)
static var touch_controls: bool = OS.has_feature("mobile")  # on-screen touch input (mobile-port)
static var graphics_quality: int = -1  # -1 = auto (picked from platform), else a quality preset index
static var touch_opacity: float = 0.6  # on-screen stick / button alpha (mobile-port)

static func load_and_apply():
	var cfg = ConfigFile.new()
	Keybinds.capture_defaults()  # before any saved rebinding touches the input map
	if cfg.load(PATH) == OK:
		Keybinds.load_from(cfg)
		master_volume = cfg.get_value("audio", "master_volume", master_volume)
		sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
		ui_volume = cfg.get_value("audio", "ui_volume", ui_volume)
		ambient_volume = cfg.get_value("audio", "ambient_volume", ambient_volume)
		fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
		vsync = cfg.get_value("video", "vsync", vsync)
		if int(cfg.get_value("meta", "version", 1)) < 2:
			vsync = false
		language = cfg.get_value("interface", "language", language)
		ui_scale = clampf(float(cfg.get_value("interface", "ui_scale", ui_scale)), 0.8, 1.5)
		player_name = cfg.get_value("player", "name", player_name)
		last_server_ip = cfg.get_value("network", "last_ip", last_server_ip)
		last_server_port = cfg.get_value("network", "last_port", last_server_port)
		third_person = cfg.get_value("video", "third_person", third_person)
		juice_splatter = cfg.get_value("video", "juice_splatter", juice_splatter)
		camera_locked = cfg.get_value("controls", "camera_locked", camera_locked)
		touch_controls = cfg.get_value("controls", "touch_controls", touch_controls)
		graphics_quality = cfg.get_value("video", "graphics_quality", graphics_quality)
		touch_opacity = cfg.get_value("controls", "touch_opacity", touch_opacity)
	Locale.setup(language)
	apply()

static func apply():
	AudioServer.set_bus_volume_db(0, linear_to_db(max(master_volume, 0.0001)))
	Sfx.ensure_buses()
	for pair in [["SFX", sfx_volume], ["UI", ui_volume], ["Ambient", ambient_volume]]:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(pair[0]), linear_to_db(max(float(pair[1]), 0.0001)))
	if DisplayServer.get_name() == "headless":
		return
	# Only when it really changes: re-setting "windowed" on every volume tick un-maximized the window
	if not OS.has_feature("mobile"):
		var mode = DisplayServer.window_get_mode()
		var is_full = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if fullscreen != is_full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_MAXIMIZED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	UIScale.apply(Engine.get_main_loop().root)

static func save():
	var cfg = ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "ui_volume", ui_volume)
	cfg.set_value("audio", "ambient_volume", ambient_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "third_person", third_person)
	cfg.set_value("video", "juice_splatter", juice_splatter)
	cfg.set_value("controls", "camera_locked", camera_locked)
	cfg.set_value("controls", "touch_controls", touch_controls)
	cfg.set_value("video", "graphics_quality", graphics_quality)
	cfg.set_value("controls", "touch_opacity", touch_opacity)
	cfg.set_value("interface", "language", language)
	cfg.set_value("interface", "ui_scale", ui_scale)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("network", "last_ip", last_server_ip)
	cfg.set_value("network", "last_port", last_server_port)
	Keybinds.save_to(cfg)
	cfg.save(PATH)
