shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Water colors
uniform vec3 shallow_color : source_color = vec3(0.2, 0.5, 0.85);
uniform vec3 deep_color : source_color = vec3(0.1, 0.3, 0.6);
uniform vec3 foam_color : source_color = vec3(0.9, 0.95, 1.0);

// Wave parameters
uniform float wave_speed : hint_range(0.1, 5.0) = 1.0;
uniform float wave_height : hint_range(0.0, 0.5) = 0.1;
uniform float wave_frequency : hint_range(0.5, 10.0) = 3.0;

// Foam parameters
uniform float foam_amount : hint_range(0.0, 1.0) = 0.3;
uniform float foam_scale : hint_range(1.0, 20.0) = 5.0;

// Transparency
uniform float water_clarity : hint_range(0.0, 1.0) = 0.7;

// Noise textures
uniform sampler2D wave_noise : hint_default_white;
uniform sampler2D foam_noise : hint_default_white;

varying vec3 world_pos;
varying float wave_offset;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Calculate wave displacement
	float time = TIME * wave_speed;
	vec2 wave_uv = world_pos.xz * wave_frequency * 0.1;

	float wave1 = sin(wave_uv.x + time) * cos(wave_uv.y + time * 0.7);
	float wave2 = sin(wave_uv.x * 1.3 - time * 0.8) * cos(wave_uv.y * 0.9 + time);

	wave_offset = (wave1 + wave2) * 0.5 * wave_height;
	VERTEX.y += wave_offset;

	// Wave normals
	vec3 tangent = normalize(vec3(1.0, cos(wave_uv.x + time) * wave_height * wave_frequency, 0.0));
	vec3 bitangent = normalize(vec3(0.0, cos(wave_uv.y + time * 0.7) * wave_height * wave_frequency, 1.0));
	NORMAL = normalize(cross(bitangent, tangent));
}

void fragment() {
	float time = TIME * wave_speed;

	// Animated UVs for foam
	vec2 foam_uv1 = world_pos.xz * foam_scale * 0.1 + vec2(time * 0.1, time * 0.05);
	vec2 foam_uv2 = world_pos.xz * foam_scale * 0.15 - vec2(time * 0.08, time * 0.12);

	float foam1 = texture(foam_noise, foam_uv1).r;
	float foam2 = texture(foam_noise, foam_uv2).r;
	float foam = (foam1 + foam2) * 0.5;

	// Foam at wave peaks
	float wave_foam = smoothstep(0.3, 0.8, wave_offset / wave_height + 0.5);
	foam = max(foam, wave_foam * foam_amount);

	// Depth-based color (simplified - uses wave offset as proxy)
	float depth_factor = smoothstep(-wave_height, wave_height, wave_offset);
	vec3 water_color = mix(deep_color, shallow_color, depth_factor);

	// Add foam
	vec3 final_color = mix(water_color, foam_color, foam * foam_amount);

	// Fresnel effect for reflections
	float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
	final_color = mix(final_color, vec3(0.8, 0.9, 1.0), fresnel * 0.3);

	ALBEDO = final_color;
	ROUGHNESS = 0.1;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ALPHA = water_clarity + fresnel * 0.2;
}
