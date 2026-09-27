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

varying vec3 obj_pos;

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

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	// 1 = grain clearly visible, 0 = grain smaller than a pixel
	float detail = clamp(1.6 - length(fwidth(obj_pos * grain_scale)), 0.0, 1.0);
	float h = paper(obj_pos);
	ALBEDO = COLOR.rgb * tint.rgb * (1.0 + (h - 0.5) * 2.0 * grain_strength * detail);

	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 surf_grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - bump_strength * detail * 0.01 * surf_grad);

	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	RIM = rim_strength;
	RIM_TINT = 0.5;
}
