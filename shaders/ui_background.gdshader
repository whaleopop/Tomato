// Animated "garden aurora" background for menus: soft drifting color blobs on a deep night gradient.
shader_type canvas_item;

uniform vec4 base_top : source_color = vec4(0.035, 0.045, 0.10, 1.0);
uniform vec4 base_bottom : source_color = vec4(0.02, 0.07, 0.07, 1.0);
uniform vec4 blob_green : source_color = vec4(0.28, 0.85, 0.45, 1.0);
uniform vec4 blob_tomato : source_color = vec4(1.0, 0.36, 0.34, 1.0);
uniform vec4 blob_corn : source_color = vec4(1.0, 0.78, 0.28, 1.0);
uniform vec4 blob_beet : source_color = vec4(0.58, 0.32, 0.95, 1.0);
uniform float intensity : hint_range(0.0, 1.5) = 0.55;
uniform float speed : hint_range(0.0, 2.0) = 0.35;
uniform float grain : hint_range(0.0, 0.2) = 0.035;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float blob(vec2 uv, vec2 center, float radius) {
	float d = length(uv - center);
	float f = smoothstep(radius, 0.0, d);
	return f * f;
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = res.x / res.y;
	vec2 uv = vec2(UV.x * aspect, UV.y);
	float t = TIME * speed;

	vec3 col = mix(base_top.rgb, base_bottom.rgb, UV.y);

	vec2 c1 = vec2(aspect * (0.22 + 0.10 * sin(t * 0.7)), 0.30 + 0.12 * cos(t * 0.5));
	vec2 c2 = vec2(aspect * (0.78 + 0.08 * cos(t * 0.6)), 0.25 + 0.10 * sin(t * 0.8));
	vec2 c3 = vec2(aspect * (0.62 + 0.12 * sin(t * 0.4 + 1.3)), 0.82 + 0.08 * cos(t * 0.7));
	vec2 c4 = vec2(aspect * (0.18 + 0.10 * cos(t * 0.5 + 2.1)), 0.85 + 0.06 * sin(t * 0.9));

	col += blob_green.rgb * blob(uv, c1, 0.75) * intensity;
	col += blob_tomato.rgb * blob(uv, c2, 0.62) * intensity * 0.85;
	col += blob_beet.rgb * blob(uv, c3, 0.70) * intensity * 0.8;
	col += blob_corn.rgb * blob(uv, c4, 0.50) * intensity * 0.6;

	// Soft vignette
	vec2 v = UV - 0.5;
	col *= 1.0 - dot(v, v) * 0.9;

	// Film grain keeps the gradients from banding
	col += (hash(UV * res + fract(TIME)) - 0.5) * grain;

	COLOR = vec4(col, 1.0);
}
