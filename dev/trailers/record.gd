## Entry point: godot --path . --write-movie trailers/<reel>.avi --fixed-fps 60 \
##     -s res://dev/trailers/record.gd -- <heroes|weapons|loot|zone> [--size=1920x1080]
## (dev/trailers/record_all.ps1 records every reel and converts them to MP4)
extends SceneTree

var _started := false

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		var reel = "heroes"
		var size = Vector2i(1920, 1080)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--size="):
				var parts = a.substr(7).split("x")
				size = Vector2i(int(parts[0]), int(parts[1]))
			elif not a.begins_with("-"):
				reel = a
		# The UI is laid out for 1280x720: scale it, render the 3D at the full size
		root.size = size
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.content_scale_size = Vector2i(1280, 720)
		# Loaded at run time: the director uses classes that need the autoloads
		var director = load("res://dev/trailers/TrailerDirector.gd").new()
		director.name = "TrailerDirector"
		root.add_child(director)
		director.run(reel)
	return false
