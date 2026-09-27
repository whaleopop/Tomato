// Fog of war, drawn as one full-screen transparent pass (see world/visibility/FogOverlay.gd).
// fog_map: one texel per hex in axial coords, R = in sight, G = explored.
//   unexplored            -> drifting clouds, almost opaque
//   explored, out of sight -> dim blue veil
//   in sight              -> clear
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D fog_map : filter_linear, repeat_disable;
uniform float fog_origin = 22.0;
uniform float fog_size = 45.0;
uniform float hex_radius = 1.0;
uniform vec3 cloud_dark : source_color = vec3(0.13, 0.15, 0.24);
uniform vec3 cloud_light : source_color = vec3(0.36, 0.40, 0.54);
uniform vec3 veil_color : source_color = vec3(0.03, 0.05, 0.11);
uniform float cloud_alpha : hint_range(0.0, 1.0) = 0.93;
uniform float veil_alpha : hint_range(0.0, 1.0) = 0.5;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);  // cover the whole screen
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).x;
	if (depth <= 0.000001) {
		discard;  // sky / the void around the island
	}
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 world4 = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 world = world4.xyz / world4.w;

	// World -> fractional axial hex coords (HexGrid.world_to_hex without rounding)
	float q = (0.57735027 * world.x - world.z / 3.0) / hex_radius;
	float r = (0.66666667 * world.z) / hex_radius;
	vec2 fog = texture(fog_map, (vec2(q, r) + fog_origin + 0.5) / fog_size).rg;
	float sight = fog.r;
	float explored = fog.g;

	vec2 drift = vec2(TIME * 0.045, TIME * 0.028);
	float n = fbm(world.xz * 0.16 + drift);
	float n2 = fbm(world.xz * 0.45 - drift * 1.7);
	vec3 clouds = mix(cloud_dark, cloud_light, smoothstep(0.3, 0.85, n * 0.75 + n2 * 0.35));
	float clouds_a = cloud_alpha * (0.9 + 0.1 * n2);

	ALBEDO = mix(clouds, veil_color, explored);
	ALPHA = mix(clouds_a, veil_alpha, explored) * (1.0 - sight);
}
