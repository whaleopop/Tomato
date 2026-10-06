// Juice stain on a flat quad (PlaneMesh, UV 0..1): an irregular blob with a few satellite drops,
// a darker rim and a glossy wet highlight. Procedural, no textures. Stylized: hard-ish cel edge.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform vec4 juice_color : source_color = vec4(0.9, 0.2, 0.2, 1.0);
uniform float seed = 0.0;
uniform float fade = 1.0;
uniform float drops = 5.0; // satellite droplets around the blob (0 = a clean print)

float h11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	float a = atan(p.y, p.x);
	// wobbly outline: a few sines with random phases = a cheap irregular blob
	float wob = 0.5 * sin(a * 3.0 + seed * 6.28) + 0.3 * sin(a * 5.0 + seed * 17.0) + 0.2 * sin(a * 9.0 + seed * 31.0);
	float d = r - (0.24 + 0.06 * wob);
	for (int i = 0; i < 5; i++) {
		if (float(i) >= drops) {
			break;
		}
		float fi = float(i);
		float ang = h11(seed * 13.0 + fi) * 6.2832;
		float dist = 0.29 + h11(seed * 7.0 + fi * 3.1) * 0.15;
		float rad = 0.014 + h11(seed * 5.0 + fi * 1.7) * 0.03;
		d = min(d, length(p - vec2(cos(ang), sin(ang)) * dist) - rad);
	}
	float mask = 1.0 - smoothstep(-0.006, 0.006, d);
	float rim = smoothstep(-0.04, -0.004, d); // 0 inside .. 1 at the edge
	vec3 col = mix(juice_color.rgb, juice_color.rgb * 0.55, rim);
	// wet highlight: a small bright patch toward the light-ish corner, only deep inside the blob
	vec2 hp = (p - vec2(-0.07, -0.08)) * vec2(1.0, 1.7);
	float hl = (1.0 - smoothstep(0.012, 0.03, length(hp) - 0.04)) * (1.0 - smoothstep(-0.06, -0.03, d) * 0.0) * step(d, -0.04);
	ALBEDO = mix(col, vec3(1.0), hl * 0.8);
	ROUGHNESS = mix(0.18, 0.05, hl);
	SPECULAR = 0.9;
	ALPHA = mask * fade;
}
