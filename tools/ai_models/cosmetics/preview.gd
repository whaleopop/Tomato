extends SceneTree
## Renders a hero wearing a cosmetic (ItemRenderer, like the shop card's picture) to a PNG.
##   godot --path . --resolution 640x360 -s tools/ai_models/cosmetics/preview.gd -- --kind=hat --id=X --hero=Tomato --out=C:/...png
## (make_cosmetic.py runs it; needs a window - the renderer doesn't draw headless. Game classes are
## loaded at run time: a -s script must not name them.)

var _args := {}
var _t := 0.0
var _started := false
var _done := false

func _initialize():
	for a in OS.get_cmdline_user_args():
		var kv = a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]

func _process(delta):
	_t += delta
	if _t > 0.5 and not _started:
		_started = true
		var renderer = load("res://ui/components/ItemRenderer.gd").get_instance(self)
		var hat = String(_args.get("id")) if _args.get("kind") == "hat" else "no_hat"
		var skin = String(_args.get("id")) if _args.get("kind") == "skin" else "classic"
		renderer.hero(String(_args.get("hero", "Tomato")), skin, hat, func(tex):
			tex.get_image().save_png(String(_args.get("out")))
			print("[preview] saved ", _args.get("out"))
			_done = true)
	if _done or _t > 30.0:
		quit()
	return false
