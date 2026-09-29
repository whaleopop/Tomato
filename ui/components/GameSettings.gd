## Persistent player settings (user://settings.cfg)
extends RefCounted
class_name GameSettings

const PATH = "user://settings.cfg"
## 2: VSync became off by default. Older files always stored vsync=true (every save wrote the
## old default), so on migration it is switched off once.
const VERSION = 2

static var master_volume: float = 0.8
static var fullscreen: bool = false
static var vsync: bool = false
static var language: String = "ru"
static var player_name: String = ""
static var last_server_ip: String = "127.0.0.1"
static var last_server_port: int = 7777
static var third_person: bool = false  # CameraController's view (V)

static func load_and_apply():
	var cfg = ConfigFile.new()
	if cfg.load(PATH) == OK:
		master_volume = cfg.get_value("audio", "master_volume", master_volume)
		fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
		vsync = cfg.get_value("video", "vsync", vsync)
		if int(cfg.get_value("meta", "version", 1)) < 2:
			vsync = false
		language = cfg.get_value("interface", "language", language)
		player_name = cfg.get_value("player", "name", player_name)
		last_server_ip = cfg.get_value("network", "last_ip", last_server_ip)
		last_server_port = cfg.get_value("network", "last_port", last_server_port)
		third_person = cfg.get_value("video", "third_person", third_person)
	Locale.setup(language)
	apply()

static func apply():
	AudioServer.set_bus_volume_db(0, linear_to_db(max(master_volume, 0.0001)))
	if DisplayServer.get_name() == "headless":
		return
	# Only when it really changes: re-setting "windowed" on every volume tick un-maximized the window
	var mode = DisplayServer.window_get_mode()
	var is_full = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen != is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

static func save():
	var cfg = ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "third_person", third_person)
	cfg.set_value("interface", "language", language)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("network", "last_ip", last_server_ip)
	cfg.set_value("network", "last_port", last_server_port)
	cfg.save(PATH)
