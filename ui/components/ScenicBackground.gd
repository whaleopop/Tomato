## The living backdrop of the whole-screen menus: the main menu's 3D garden (MenuDiorama, the
## camera leans with the mouse) under a night wash, so every screen shares one world. Clicks go
## through it. `fallback` is the cheap animated gradient behind the scene.
extends Control
class_name ScenicBackground

var fallback: ColorRect
var scene: MenuDiorama

func _init():
	name = "Background"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fallback = ColorRect.new()
	fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = ShaderMaterial.new()
	mat.shader = UITheme.BACKGROUND_SHADER
	fallback.material = mat
	add_child(fallback)
	scene = MenuDiorama.new()
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scene)
	# Evening wash: darker on the left and under the bar so the panels read, the garden still
	# glows through (the screens should feel like the main menu's world, not a black room)
	for spec in [[Vector2(0, 0), Vector2(1, 0), 0.62, 0.12], [Vector2(0, 0), Vector2(0, 1), 0.46, 0.3]]:
		var shade = TextureRect.new()
		var grad = GradientTexture2D.new()
		grad.gradient = Gradient.new()
		grad.gradient.set_color(0, Color(0.02, 0.03, 0.07, spec[2]))
		grad.gradient.set_color(1, Color(0.02, 0.03, 0.07, spec[3]))
		grad.fill_from = spec[0]
		grad.fill_to = spec[1]
		shade.texture = grad
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
