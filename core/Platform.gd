## Platform / mobile detection helpers (P0 mobile-port foundation)
extends RefCounted
class_name Platform

static func is_mobile() -> bool:
	return OS.has_feature("mobile")

static func touch_mode() -> bool:
	if is_mobile():
		return true
	if OS.get_cmdline_args().has("--touch"):
		return true
	if GameSettings.touch_controls:
		return true
	return false

static func renderer_name() -> String:
	return RenderingServer.get_current_rendering_method()
