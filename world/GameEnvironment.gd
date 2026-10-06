## Game environment - handles sun, sky, clouds, and atmosphere
extends Node3D
class_name GameEnvironment

var sun: DirectionalLight3D = null
var world_environment: WorldEnvironment = null
var cloud_particles: GPUParticles3D = null

# Time of day (0-24 hours)
var time_of_day: float = 10.0  # Start at 10 AM
var day_cycle_speed: float = 0.0  # 0 = no cycle, set to 0.01 for slow cycle

# The match runs from a bright day into a sunset: `dusk` follows how far the zone has closed in
# (NetworkManager.zone_changed), the sun sinks and warms, the sky reddens. Night / fog events
# (MapEvents) darken on top of it and hand the light back to us when they end.
const DAY_SUN = Color(1.0, 0.95, 0.85)
const DUSK_SUN = Color(1.0, 0.6, 0.36)
const DAY_TOP = Color(0.4, 0.6, 0.9)
const DUSK_TOP = Color(0.34, 0.36, 0.62)
const DAY_HORIZON = Color(0.7, 0.8, 0.95)
const DUSK_HORIZON = Color(1.0, 0.62, 0.45)
var dusk: float = 0.0            # 0 bright day .. 1 sunset
var _dusk_target: float = 0.0
var _zone_start: int = -1        # the first safe radius of the match
var _sky_material: ProceduralSkyMaterial = null
var ambient_life: AmbientLife = null

func _ready():
	_create_sun()
	_create_environment()
	_create_clouds()
	RenderQuality.apply_sun(sun)
	RenderQuality.apply_environment(world_environment.environment)
	RenderQuality.apply_viewport(get_viewport())
	ambient_life = AmbientLife.new()
	ambient_life.name = "AmbientLife"
	add_child(ambient_life)
	var ambient_sound = AmbientSound.new()
	ambient_sound.name = "AmbientSound"
	add_child(ambient_sound)
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.has_signal("zone_changed"):
		network_manager.zone_changed.connect(_on_zone_changed)

func _on_zone_changed(kind: String, _coords: Array, _seconds: float, _center: Vector2i, radius: int):
	if kind.begins_with("core"):
		_dusk_target = 1.0
		return
	if _zone_start < 0 or radius > _zone_start:
		_zone_start = radius
	if _zone_start > 1:
		_dusk_target = clamp(1.0 - float(radius - 1) / float(_zone_start - 1), 0.0, 1.0)

## What the sun looks like right now without events (MapEvents returns to this after a night)
func day_light() -> Array:
	return [DAY_SUN.lerp(DUSK_SUN, dusk), lerp(1.2, 0.95, dusk)]

func _update_dusk(delta: float) -> void:
	dusk = move_toward(dusk, _dusk_target, delta * 0.02)  # slow: a sunset, not a switch
	if sun:
		sun.rotation_degrees.x = lerp(-50.0, -16.0, dusk)
		sun.rotation_degrees.y = lerp(-30.0, -62.0, dusk)
		if MapEvents.sight_factor >= 0.999:  # no night / fog running: the light is ours
			var light = day_light()
			var k = 1.0 - exp(-delta * 1.5)
			sun.light_color = sun.light_color.lerp(light[0], k)
			sun.light_energy = lerp(sun.light_energy, light[1], k)
	if _sky_material:
		_sky_material.sky_top_color = DAY_TOP.lerp(DUSK_TOP, dusk)
		_sky_material.sky_horizon_color = DAY_HORIZON.lerp(DUSK_HORIZON, dusk)

func _process(delta: float):
	_update_dusk(delta)
	if day_cycle_speed > 0:
		time_of_day += delta * day_cycle_speed
		if time_of_day >= 24.0:
			time_of_day -= 24.0
		_update_sun_position()

func _create_sun():
	sun = DirectionalLight3D.new()
	sun.name = "Sun"

	# Sun properties
	sun.light_color = Color(1.0, 0.95, 0.85)  # Warm sunlight
	sun.light_energy = 1.2
	sun.light_indirect_energy = 1.0

	# Enable shadows
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 2.0
	sun.shadow_blur = 1.0

	# Shadow quality
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.1
	sun.directional_shadow_split_2 = 0.2
	sun.directional_shadow_split_3 = 0.5
	sun.directional_shadow_max_distance = 100.0

	# Position sun for morning light
	sun.rotation_degrees = Vector3(-45, -30, 0)

	add_child(sun)
	print("[GameEnvironment] Sun created with shadows")

func _create_environment():
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"

	var env = Environment.new()

	# Sky
	var sky = Sky.new()
	var sky_material = ProceduralSkyMaterial.new()

	# Sky colors
	sky_material.sky_top_color = Color(0.4, 0.6, 0.9)      # Light blue
	sky_material.sky_horizon_color = Color(0.7, 0.8, 0.95)  # Pale blue
	# Below the island is the void you fall into: deep night blue, matching the UI palette
	sky_material.ground_bottom_color = Color(0.02, 0.03, 0.07)
	sky_material.ground_horizon_color = Color(0.09, 0.14, 0.24)
	sky_material.ground_curve = 0.08

	# Sun in sky
	sky_material.sun_angle_max = 30.0
	sky_material.sun_curve = 0.15

	sky.sky_material = sky_material
	_sky_material = sky_material
	env.sky = sky
	env.background_mode = Environment.BG_SKY

	# Ambient light from sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.ambient_light_sky_contribution = 0.7

	# Tonemap for better colors
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0

	# SSAO for depth
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 2.0

	# Screen-space reflections: only glossy surfaces use them - the water (roughness ~0.04)
	# mirrors heroes, walls and trees on the shore; the matte ground is unaffected
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2

	# SDFGI for global illumination (can be heavy)
	env.sdfgi_enabled = false

	# Glow for bloom effect
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_strength = 1.0
	env.glow_bloom = 0.1

	# Fog for atmosphere
	env.fog_enabled = true
	env.fog_light_color = Color(0.45, 0.55, 0.75)
	env.fog_light_energy = 0.5
	env.fog_sun_scatter = 0.3
	env.fog_density = 0.001
	env.fog_aerial_perspective = 0.5

	world_environment.environment = env
	add_child(world_environment)
	print("[GameEnvironment] World environment created")

func _create_clouds():
	cloud_particles = GPUParticles3D.new()
	cloud_particles.name = "Clouds"
	cloud_particles.amount = 30
	cloud_particles.lifetime = 60.0
	cloud_particles.explosiveness = 0.0
	cloud_particles.randomness = 1.0

	var material = ParticleProcessMaterial.new()

	# Cloud emission area (large box high in the sky)
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(100, 5, 100)

	# Slow horizontal drift
	material.direction = Vector3(1, 0, 0.2)
	material.spread = 10.0
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = 2.0
	material.gravity = Vector3.ZERO

	# Cloud sizes
	material.scale_min = 8.0
	material.scale_max = 20.0

	# White fluffy clouds
	material.color = Color(1.0, 1.0, 1.0, 0.6)

	cloud_particles.process_material = material

	# Simple cloud mesh (flat billboard)
	var mesh = QuadMesh.new()
	mesh.size = Vector2(1, 0.5)

	# Cloud material (billboard facing camera)
	var cloud_mat = StandardMaterial3D.new()
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.7)
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	cloud_mat.billboard_keep_scale = true
	mesh.material = cloud_mat

	cloud_particles.draw_pass_1 = mesh

	# Position clouds high in sky
	cloud_particles.position = Vector3(0, 50, 0)

	add_child(cloud_particles)
	print("[GameEnvironment] Clouds created")

func _update_sun_position():
	if not sun:
		return

	# Calculate sun angle based on time of day
	# 6 AM = sunrise, 12 PM = noon, 6 PM = sunset
	var sun_angle = (time_of_day - 6.0) / 12.0 * 180.0 - 90.0
	sun_angle = clamp(sun_angle, -90, 90)

	sun.rotation_degrees.x = -sun_angle

	# Adjust sun color based on time
	if time_of_day < 7 or time_of_day > 17:
		# Dawn/dusk - orange
		sun.light_color = Color(1.0, 0.6, 0.3)
		sun.light_energy = 0.6
	elif time_of_day < 9 or time_of_day > 15:
		# Morning/evening - warm
		sun.light_color = Color(1.0, 0.85, 0.7)
		sun.light_energy = 0.9
	else:
		# Midday - bright
		sun.light_color = Color(1.0, 0.95, 0.85)
		sun.light_energy = 1.2
