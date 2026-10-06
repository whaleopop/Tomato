// Juice splotches on a hero (material_overlay): patches from 3D value noise in the mesh's local
// space, so they stick to the body while it moves. `amount` 1 -> 0 shrinks them away. Glossy.
shader_type spatial;
render_mode blend_mix, depth_draw_never;

uniform vec4 juice_color : source_color = vec4(0.9, 0.2, 0.2, 1.0);
uniform float amount = 1.0;
uniform float seed = 0.0;

varying vec3 lpos;

float h31(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float n = vnoise(lpos * 4.0 + seed) * 0.7 + vnoise(lpos * 9.0 + seed * 2.0) * 0.3;
	float thr = mix(1.0, 0.42, amount);
	float m = smoothstep(thr, thr + 0.05, n);
	ALBEDO = juice_color.rgb;
	ROUGHNESS = 0.12;
	SPECULAR = 0.9;
	ALPHA = m * 0.9;
}
