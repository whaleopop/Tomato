// Weapon finishes (Cosmetics.apply_to_weapon): tints the gun's own texture while preserving
// detail. Dark base pixels (gun body) absorb the tint; bright pixels (highlights, whites) keep
// their original color so markings and logos stay readable.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float metal = 0.0;
uniform float rough = 0.6;
uniform vec3 glow = vec3(0.0);
uniform int pattern = 0;
uniform float pattern_scale = 6.0;
uniform vec4 pattern_color : source_color = vec4(0.0);

#include "res://shaders/patterns.gdshaderinc"

varying vec3 pattern_pos;

void vertex() {
	pattern_pos = VERTEX * length(MODEL_MATRIX[0].xyz);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 base_color = tex.rgb * albedo.rgb;

	// Luminance-based paint mask: dark areas (gun body) accept the tint fully;
	// bright areas (highlights, decals) are left mostly untouched.
	float lum = dot(base_color, vec3(0.299, 0.587, 0.114));
	float paint_mask = 1.0 - smoothstep(0.55, 0.85, lum);

	vec3 tinted = base_color * tint.rgb;
	vec3 base = mix(base_color, tinted, paint_mask);

	float sparkle = 0.0;
	if (pattern > 0) {
		float cover = pattern_mask(pattern, pattern_pos, pattern_scale, sparkle);
		// Patterns also respect the luminance mask — no pattern on bright highlights
		base = mix(base, pattern_color.rgb, cover * pattern_color.a * paint_mask);
	}
	ALBEDO = base;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = glow + vec3(1.0, 0.95, 0.8) * sparkle * 3.0;
}
