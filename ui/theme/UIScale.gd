## Global UI scaling: the project draws at a 1920x1080 virtual size (stretch canvas_items) and
## this keeps the menus / HUD at a comfortable physical size on 720p..4K, times the user's setting.
extends RefCounted
class_name UIScale

const BASE := Vector2i(1920, 1080)
const PRESETS := [0.8, 0.9, 1.0, 1.1, 1.25, 1.5]

static func apply(root: Window) -> void:
	if root == null or DisplayServer.get_name() == "headless":
		return
	if root.content_scale_size != BASE:
		return  # something (the trailer recorder) set its own
	var w := float(root.size.x)
	var h := float(root.size.y)
	if w < 1.0 or h < 1.0:
		return  # minimized
	var fit1080: float = minf(w / BASE.x, h / BASE.y)
	var factor: float
	if Platform.is_mobile():
		# Phones: fit ~720-900 virtual pixels of height (bigger touch targets than desktop's
		# 1080 virtual pixels), scaled a bit further by the user's own UI scale setting.
		var fit720v: float = minf(w / 1280.0, h / 720.0)
		var mobile_scale: float = clampf(GameSettings.ui_scale, 0.8, 1.0)
		var s_mobile: float = fit720v * mobile_scale
		factor = s_mobile / fit1080
	else:
		var fit720: float = minf(w / 1280.0, h / 720.0)
		var auto: float = maxf(fit1080, minf(1.0, fit720))
		var s: float = minf(auto * GameSettings.ui_scale, fit720)
		factor = s / fit1080
	if absf(root.content_scale_factor - factor) > 0.001:
		root.content_scale_factor = factor

## Safe-area margins (notches / rounded corners) in virtual (layout) units, for corner-anchored
## HUD elements. Zero on desktop (no safe-area concept: get_display_safe_area() is the full rect).
static func safe_margins(node: Node) -> Vector4:
	if node == null or not node.is_inside_tree():
		return Vector4.ZERO
	var window := node.get_tree().root
	var window_rect := Rect2i(Vector2i.ZERO, window.size)
	var safe := DisplayServer.get_display_safe_area()
	var scale := render_scale(node)
	if scale <= 0.0:
		return Vector4.ZERO
	var left: float = maxf(0.0, safe.position.x - window_rect.position.x) / scale
	var top: float = maxf(0.0, safe.position.y - window_rect.position.y) / scale
	var right: float = maxf(0.0, window_rect.end.x - safe.end.x) / scale
	var bottom: float = maxf(0.0, window_rect.end.y - safe.end.y) / scale
	return Vector4(left, top, right, bottom)

## Physical pixels per virtual (layout) unit
static func render_scale(node: Node) -> float:
	if node == null or not node.is_inside_tree():
		return 1.0
	var root := node.get_tree().root
	var v := root.get_visible_rect().size.y
	if v <= 0.0 or root.size.y <= 0:
		return 1.0
	return float(root.size.y) / v
