shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Tile properties
uniform vec3 tile_color : source_color = vec3(0.3, 0.7, 0.25);
uniform float tile_height : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width : hint_range(0.0, 0.2) = 0.05;
uniform vec3 edge_color : source_color = vec3(0.15, 0.35, 0.12);

// Effects
uniform float damage_amount : hint_range(0.0, 1.0) = 0.0;
uniform float hover_highlight : hint_range(0.0, 1.0) = 0.0;
uniform float destruction_progress : hint_range(0.0, 1.0) = 0.0;

// Noise for variation
uniform sampler2D noise_texture : hint_default_white;
uniform float noise_scale : hint_range(0.1, 10.0) = 2.0;
uniform float noise_strength : hint_range(0.0, 0.5) = 0.1;

varying vec3 world_position;
varying vec3 local_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_position = VERTEX;

	// Destruction animation - sink and scale down
	if (destruction_progress > 0.0) {
		VERTEX.y -= destruction_progress * 2.0;
		VERTEX.xz *= 1.0 - destruction_progress * 0.5;
	}
}

void fragment() {
	// Base color with noise variation
	vec2 noise_uv = world_position.xz * noise_scale * 0.1;
	float noise_value = texture(noise_texture, noise_uv).r;
	vec3 color = tile_color + (noise_value - 0.5) * noise_strength;

	// Edge darkening based on distance from center (for hex shape)
	float dist_from_center = length(local_position.xz);
	float edge_factor = smoothstep(0.8 - edge_width, 0.8, dist_from_center);
	color = mix(color, edge_color, edge_factor * 0.5);

	// Top face highlighting
	float top_factor = smoothstep(0.0, 0.1, local_position.y);
	color = mix(color * 0.8, color, top_factor);

	// Damage effect - redden and darken
	if (damage_amount > 0.0) {
		vec3 damage_color = vec3(0.8, 0.2, 0.1);
		color = mix(color, damage_color, damage_amount * 0.5);
	}

	// Hover highlight
	if (hover_highlight > 0.0) {
		color += vec3(0.2) * hover_highlight;
	}

	// Destruction fade
	float alpha = 1.0 - destruction_progress;

	ALBEDO = color;
	ROUGHNESS = 0.8;
	METALLIC = 0.0;
	ALPHA = alpha;
}
