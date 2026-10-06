## Mobile-port render quality tiers: resolves GameSettings.graphics_quality (or an automatic
## platform default) into concrete Environment / DirectionalLight3D / Viewport tweaks, and gives
## decor / ambience / juice systems a cheap way to ask "how much can we afford".
## HIGH is always a no-op against the desktop Forward+ defaults already baked into the scene code.
extends RefCounted
class_name RenderQuality

const LOW: int = 0
const MEDIUM: int = 1
const HIGH: int = 2

## The effective quality level: GameSettings.graphics_quality if set, else a platform default.
static func level() -> int:
	var q: int = GameSettings.graphics_quality
	if q >= 0:
		return q
	return MEDIUM if Platform.is_mobile() else HIGH

## Turn off the expensive Forward+-only screen-space effects where they cost more than they're
## worth: always off-Forward+ (they silently no-op there anyway, so this is just explicit), and
## on LOW/MEDIUM even on desktop Forward+.
static func apply_environment(env: Environment) -> void:
	if not env:
		return
	var lvl = level()
	var not_forward_plus = Platform.renderer_name() != "forward_plus"
	if lvl < HIGH or not_forward_plus:
		if "ssao_enabled" in env:
			env.ssao_enabled = false
		if "ssr_enabled" in env:
			env.ssr_enabled = false
	if lvl == LOW:
		if "glow_enabled" in env:
			env.glow_enabled = false

## Cheaper shadows on MEDIUM, none on LOW. HIGH leaves the sun exactly as GameEnvironment built it.
static func apply_sun(sun: DirectionalLight3D) -> void:
	if not sun:
		return
	match level():
		LOW:
			sun.shadow_enabled = false
		MEDIUM:
			sun.directional_shadow_max_distance = 40.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS

## Render-scale and MSAA for the given viewport. HIGH leaves the viewport defaults untouched.
static func apply_viewport(vp: Viewport) -> void:
	if not vp:
		return
	match level():
		LOW:
			vp.scaling_3d_scale = 0.6
			vp.msaa_3d = Viewport.MSAA_DISABLED
		MEDIUM:
			vp.scaling_3d_scale = 0.75
			vp.msaa_3d = Viewport.MSAA_DISABLED
		HIGH:
			vp.scaling_3d_scale = 1.0

## How far decor (BiomeDecor) should stay visible; 0.0 means "no limit, use the existing default".
static func decor_range() -> float:
	match level():
		LOW:
			return 25.0
		MEDIUM:
			return 40.0
		_:
			return 0.0
