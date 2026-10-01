// The backdrop of a ParallaxCard. Every card: a gradient in its accent color, slow light rays from
// behind the art, a faint honeycomb (the island's hexes) and a vignette. Mastery ranks
// (Mastery.gd, tier 0..4) swap the gradient for a material: brushed bronze / silver / gold with a
// sweeping shine, obsidian with glowing cracks, diamond facets that shift through the rainbow.
shader_type canvas_item;

uniform vec4 accent : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform int tier = -1;
uniform float seed = 0.0;
uniform vec2 aspect = vec2(0.72, 1.0);   // card width / height, for round hexes and circles

// Integer hash (the fract(sin) kind draws lines)
float hash21(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p))) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) * (1.0 / 4294967295.0);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

// Distance to the nearest edge of a hex cell
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec2 a = mod(p, s) - s * 0.5;
	vec2 b = mod(p - s * 0.5, s) - s * 0.5;
	vec2 h = dot(a, a) < dot(b, b) ? a : b;
	h = abs(h);
	return 0.5 - max(dot(h, s * 0.5), h.x);
}

// Voronoi: x = distance to the nearest seed, y = to the second (edges where they meet), z = cell id
vec3 voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash21(i + g + seed), hash21(i + g + 17.0 + seed));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; id = hash21(i + g + 3.0); }
			else if (d < d2) { d2 = d; }
		}
	}
	return vec3(d1, d2, id);
}

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV;
	vec2 p = (uv - vec2(0.5, 0.42)) * aspect;   // centered on where the art stands
	float r = length(p);
	float t = TIME;
	vec3 col;

	vec3 metal_base = vec3(0.0);
	if (tier == 0) metal_base = vec3(0.62, 0.36, 0.2);
	else if (tier == 1) metal_base = vec3(0.62, 0.66, 0.72);
	else if (tier == 2) metal_base = vec3(0.85, 0.62, 0.18);

	if (tier >= 0 && tier <= 2) {
		// Brushed metal: horizontal streaks, darker towards the bottom, a sweeping shine
		float streak = noise(vec2(uv.x * 3.0, uv.y * 140.0)) * 0.5 + noise(vec2(uv.x * 9.0, uv.y * 400.0)) * 0.25;
		col = metal_base * (0.55 + 0.45 * (1.0 - uv.y)) * (0.8 + streak * 0.4);
		float band = uv.x * 0.8 + uv.y * 0.6 - mod(t * 0.35 + seed, 2.6) + 0.6;
		col += vec3(1.0, 0.95, 0.85) * smoothstep(0.12, 0.0, abs(band)) * (0.35 + 0.25 * float(tier));
		// Embossed honeycomb
		float he = hex_edge(p * 9.0);
		col += metal_base * smoothstep(0.06, 0.0, he) * 0.35;
		col -= smoothstep(0.1, 0.04, he) * smoothstep(0.0, 0.04, he) * 0.06;
	} else if (tier == 3) {
		// Obsidian: black glass, purple cracks that breathe
		vec3 v = voronoi(p * 5.0 + vec2(0.0, seed));
		float crack = smoothstep(0.06, 0.0, v.y - v.x);
		float pulse = 0.6 + 0.4 * sin(t * 1.6 + v.z * 6.28);
		col = mix(vec3(0.03, 0.02, 0.06), vec3(0.09, 0.05, 0.16), v.z * 0.6 + (1.0 - uv.y) * 0.4);
		col += vec3(0.6, 0.25, 1.0) * crack * pulse * 1.3;
		col += vec3(0.35, 0.15, 0.7) * smoothstep(0.25, 0.0, v.y - v.x) * 0.15;
		// glassy reflection streak
		col += vec3(0.5, 0.4, 0.8) * smoothstep(0.03, 0.0, abs(uv.x * 0.7 - uv.y + 0.35 - 0.1 * sin(t * 0.3))) * 0.25;
	} else if (tier == 4) {
		// Diamond: facets with their own brightness, a rainbow sliding through them, sparkles
		vec3 v = voronoi(p * 6.0 + vec2(seed, 0.0));
		float facet = 0.55 + 0.45 * fract(v.z * 7.0 + t * 0.08);
		vec3 rainbow = hue(fract(v.z * 0.7 + uv.y * 0.4 + t * 0.12));
		col = mix(vec3(0.7, 0.9, 1.0), rainbow, 0.35) * facet;
		col *= 0.55 + 0.45 * (1.0 - uv.y);
		col += vec3(1.0) * smoothstep(0.035, 0.0, v.y - v.x) * 0.5;
		float sp = hash21(floor(uv * vec2(28.0, 38.0)) + floor(t * 3.0));
		col += vec3(1.0) * step(0.985, sp) * smoothstep(0.5, 0.0, length(fract(uv * vec2(28.0, 38.0)) - 0.5)) * 1.5;
	} else {
		// Ordinary card: the accent fading to the night, a faint honeycomb
		col = mix(accent.rgb * 0.75, vec3(0.05, 0.06, 0.12), smoothstep(0.0, 1.0, uv.y));
		float he = hex_edge(p * 8.0 + vec2(0.0, t * 0.05));
		col += accent.rgb * smoothstep(0.05, 0.0, he) * 0.12;
	}

	// Light rays from behind the art, turning slowly
	float a = atan(p.y, p.x);
	float rays = pow(max(0.0, sin(a * 9.0 + t * 0.25 + seed)), 6.0) * smoothstep(0.75, 0.05, r);
	vec3 ray_col = tier >= 0 ? mix(vec3(1.0), metal_base + vec3(0.2), 0.5) : accent.rgb + vec3(0.25);
	col += ray_col * rays * (tier >= 0 ? 0.18 : 0.12);
	// A soft halo behind the hero / gun
	col += (tier == 3 ? vec3(0.5, 0.2, 0.9) : (tier == 4 ? vec3(0.6, 0.95, 1.0) : accent.rgb)) * smoothstep(0.42, 0.0, r) * 0.25;
	// Vignette
	col *= 1.0 - smoothstep(0.45, 0.95, length((uv - 0.5) * vec2(1.0, 0.85))) * 0.55;
	COLOR = vec4(col, 1.0);
}
