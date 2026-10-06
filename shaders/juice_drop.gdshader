// A flying juice drop: a teardrop on a (crossed) quad, round head at the top (UV v = 0, the side the
// particle moves toward), tapering tail behind it, with a small glossy highlight on the head.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, unshaded;

uniform vec4 juice_color : source_color = vec4(0.9, 0.2, 0.2, 1.0);

void fragment() {
	float u = UV.x - 0.5;
	float v = UV.y;
	float hy = 0.2;
	float w;
	if (v < hy) {
		w = 0.5 * sqrt(max(0.0, 1.0 - pow((v - hy) / hy, 2.0)));
	} else {
		w = 0.5 * pow(max(0.0, 1.0 - (v - hy) / (1.0 - hy)), 1.4);
	}
	float a = 1.0 - smoothstep(w - 0.06, w, abs(u));
	float hl = 1.0 - smoothstep(0.03, 0.07, length((vec2(u, v) - vec2(-0.12, 0.12)) * vec2(1.0, 1.4)));
	ALBEDO = mix(juice_color.rgb * mix(0.7, 1.0, v < hy ? 1.0 : 0.0), vec3(1.0), hl * 0.85);
	ROUGHNESS = 0.1;
	SPECULAR = 0.9;
	ALPHA = a * juice_color.a;
}
