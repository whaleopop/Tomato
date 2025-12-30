shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Force field colors
uniform vec3 field_color : source_color = vec3(0.2, 0.6, 1.0);
uniform vec3 edge_glow_color : source_color = vec3(0.8, 0.9, 1.0);

// Animation
uniform float scroll_speed : hint_range(0.0, 2.0) = 0.5;
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.0;

// Effect strength
uniform float base_alpha : hint_range(0.0, 0.5) = 0.1;
uniform float fresnel_power : hint_range(0.5, 5.0) = 2.0;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.5;

// Pattern
uniform float hex_scale : hint_range(1.0, 50.0) = 10.0;
uniform float line_width : hint_range(0.01, 0.2) = 0.05;

varying vec3 world_pos;

// Hexagonal pattern function
float hex_pattern(vec2 p) {
	p *= hex_scale;
	vec2 h = vec2(1.0, sqrt(3.0));
	vec2 a = mod(p, h) - h * 0.5;
	vec2 b = mod(p - h * 0.5, h) - h * 0.5;

	float d1 = length(a);
	float d2 = length(b);

	return min(d1, d2);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float time = TIME;

	// Fresnel effect for edge glow
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);

	// Scrolling hex pattern
	vec2 pattern_uv = world_pos.xz + vec2(0.0, time * scroll_speed);
	float hex = hex_pattern(pattern_uv);
	float pattern = smoothstep(line_width, line_width * 0.5, hex);

	// Pulse effect
	float pulse = (sin(time * pulse_speed) + 1.0) * 0.5;

	// Combine effects
	vec3 color = mix(field_color, edge_glow_color, fresnel);

	// Add pattern
	color += pattern * 0.3 * pulse;

	// Final alpha
	float alpha = base_alpha + fresnel * fresnel_strength + pattern * 0.1;
	alpha *= 0.5 + pulse * 0.5;

	ALBEDO = color;
	ALPHA = alpha;
}
