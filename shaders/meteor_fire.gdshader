shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec3 fire_color_hot : source_color = vec3(1.0, 0.9, 0.3);
uniform vec3 fire_color_cool : source_color = vec3(1.0, 0.3, 0.0);
uniform float scroll_speed : hint_range(0.0, 10.0) = 3.0;
uniform float noise_scale : hint_range(1.0, 20.0) = 8.0;
uniform float distortion : hint_range(0.0, 1.0) = 0.3;

varying vec3 world_vertex;

// Simple noise functions
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.0;
	}

	return value;
}

void vertex() {
	world_vertex = VERTEX;
}

void fragment() {
	float time = TIME * scroll_speed;
	vec2 uv = world_vertex.xz * noise_scale;

	// Animated noise
	float n1 = fbm(uv + vec2(time * 0.5, time * 0.3));
	float n2 = fbm(uv * 1.5 + vec2(-time * 0.4, time * 0.2));

	// Combined noise with distortion
	float combined = (n1 + n2 * distortion) / (1.0 + distortion);

	// Color gradient based on noise
	vec3 color = mix(fire_color_cool, fire_color_hot, combined);

	// Fade out toward edges using UV.y (particle lifetime)
	float alpha = combined * (1.0 - UV.y * UV.y);
	alpha *= smoothstep(0.0, 0.2, UV.y) * smoothstep(1.0, 0.8, UV.y);

	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
