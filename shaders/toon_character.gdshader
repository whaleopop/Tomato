shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_toon;

// Character color
uniform vec3 base_color : source_color = vec3(0.8, 0.3, 0.3);
uniform vec3 shadow_color : source_color = vec3(0.3, 0.1, 0.1);
uniform vec3 highlight_color : source_color = vec3(1.0, 0.9, 0.8);

// Toon shading parameters
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float shadow_smoothness : hint_range(0.0, 0.5) = 0.05;
uniform float highlight_threshold : hint_range(0.5, 1.0) = 0.9;
uniform float highlight_smoothness : hint_range(0.0, 0.2) = 0.05;

// Rim light
uniform vec3 rim_color : source_color = vec3(0.8, 0.9, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.3;

// Effects
uniform float damage_flash : hint_range(0.0, 1.0) = 0.0;
uniform float invincibility : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_normal;
varying vec3 view_dir;

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	view_dir = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	// Basic toon shading with manual light calculation
	vec3 light_dir = normalize(vec3(0.5, 1.0, 0.3)); // Approximate sun direction
	float NdotL = dot(NORMAL, light_dir);

	// Shadow bands
	float shadow = smoothstep(shadow_threshold - shadow_smoothness, shadow_threshold + shadow_smoothness, NdotL);

	// Highlight bands
	float highlight = smoothstep(highlight_threshold - highlight_smoothness, highlight_threshold + highlight_smoothness, NdotL);

	// Combine colors
	vec3 color = mix(shadow_color, base_color, shadow);
	color = mix(color, highlight_color, highlight);

	// Rim lighting
	float rim = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	rim = pow(rim, rim_power) * rim_strength;
	color = mix(color, rim_color, rim);

	// Damage flash (red)
	if (damage_flash > 0.0) {
		color = mix(color, vec3(1.0, 0.2, 0.2), damage_flash * 0.7);
	}

	// Invincibility flicker
	if (invincibility > 0.0) {
		float flicker = sin(TIME * 20.0) * 0.5 + 0.5;
		color += vec3(0.3, 0.3, 0.5) * flicker * invincibility;
	}

	ALBEDO = color;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}
