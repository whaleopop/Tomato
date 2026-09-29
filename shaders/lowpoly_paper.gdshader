// Low-poly "paper craft" look of the concept art, for vertex-colored models (AI characters).
// Flat facets come from the mesh (flat normals); this adds the paper on top:
//   - grain: faint lightness variation, like colored card stock
//   - fibres: a tiny bump from the same noise (derivative bump mapping, no UVs or tangents needed)
//   - soft rim so the silhouette reads against the ground
// Detail fades with screen size, so small characters in the match don't shimmer.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float grain_scale = 60.0;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.06;
uniform float bump_strength : hint_range(0.0, 3.0) = 0.5;
uniform float roughness : hint_range(0.0, 1.0) = 0.86;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.22;
uniform vec4 tint : source_color = vec4(1.0);
// Cosmetic skins (Cosmetics.apply_to_character): per hero, the material stays shared
instance uniform vec3 skin_hsv = vec3(0.0, 1.0, 1.0);    // hue shift (turns), saturation, value
instance uniform vec4 skin_tint : source_color = vec4(1.0);
instance uniform float skin_metal = 0.0;
instance uniform vec4 skin_glow : source_color = vec4(0.0); // rim light, alpha = strength
instance uniform vec2 skin_pattern = vec2(0.0, 1.0);        // patterns.gdshaderinc kind, scale (per metre)
instance uniform vec4 skin_pattern_color : source_color = vec4(0.0); // alpha = how strongly it covers

#include "res://shaders/patterns.gdshaderinc"

varying vec3 obj_pos;
varying vec3 pattern_pos;  // obj_pos in metres (the model is scaled to hero size)

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
	               mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
	               mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Fine fibres + slightly coarser unevenness of the card, 0..1
float paper(vec3 p) {
	return value_noise(p * grain_scale) * 0.55
		+ value_noise(p * grain_scale * 2.3 + 7.1) * 0.25
		+ value_noise(p * grain_scale * 0.3 + 3.3) * 0.2;
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void vertex() {
	obj_pos = VERTEX;
	pattern_pos = VERTEX * length(MODEL_MATRIX[0].xyz);
}

void fragment() {
	// 1 = grain clearly visible, 0 = grain smaller than a pixel
	float detail = clamp(1.6 - length(fwidth(obj_pos * grain_scale)), 0.0, 1.0);
	float h = paper(obj_pos);
	vec3 base = COLOR.rgb * tint.rgb;
	vec3 hsv = rgb2hsv(base);
	hsv.x = fract(hsv.x + skin_hsv.x);
	hsv.y = clamp(hsv.y * skin_hsv.y, 0.0, 1.0);
	hsv.z = hsv.z * skin_hsv.z;
	base = hsv2rgb(hsv) * skin_tint.rgb;
	float sparkle = 0.0;
	if (skin_pattern.x > 0.5) {
		float cover = pattern_mask(int(skin_pattern.x + 0.5), pattern_pos, skin_pattern.y, sparkle);
		base = mix(base, skin_pattern_color.rgb, cover * skin_pattern_color.a);
	}
	ALBEDO = base * (1.0 + (h - 0.5) * 2.0 * grain_strength * detail);

	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 surf_grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - bump_strength * detail * 0.01 * surf_grad);

	ROUGHNESS = mix(roughness, 0.25, skin_metal);
	METALLIC = skin_metal;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = skin_glow.rgb * skin_glow.a * (0.25 + fresnel * 1.5) + vec3(1.0, 0.95, 0.8) * sparkle * 2.5;
	SPECULAR = 0.3;
	RIM = rim_strength;
	RIM_TINT = 0.5;
}
