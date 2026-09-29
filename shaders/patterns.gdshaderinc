// Procedural patterns for cosmetic skins (heroes: lowpoly_paper.gdshader, guns: weapon_finish.gdshader).
// p is a position on the model in metres (object space x the model's scale), so a pattern sticks to
// the model and has the same size on every hero and gun. Returns how much of the pattern color
// covers the point (0..1); `sparkle` gets the glowing bits (galaxy).
//   1 stripes (tiger)  2 dots  3 camo  4 checker  5 zebra  6 galaxy  7 hearts-ish waves

float pat_hash(vec3 p) {
	uvec3 q = uvec3(ivec3(floor(p)) + ivec3(4096));
	uint h = q.x * 73856093u ^ q.y * 19349663u ^ q.z * 83492791u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return float(h & 0xFFFFu) / 65535.0;
}

float pat_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(pat_hash(i), pat_hash(i + vec3(1, 0, 0)), f.x),
	               mix(pat_hash(i + vec3(0, 1, 0)), pat_hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(pat_hash(i + vec3(0, 0, 1)), pat_hash(i + vec3(1, 0, 1)), f.x),
	               mix(pat_hash(i + vec3(0, 1, 1)), pat_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float pattern_mask(int kind, vec3 p, float scale, out float sparkle) {
	sparkle = 0.0;
	vec3 q = p * scale;
	if (kind == 1) {  // tiger stripes: wavy bands across the body
		float band = fract(q.y + sin(q.x * 2.3 + q.z * 1.7) * 0.25 + pat_noise(q * 1.5) * 0.35);
		return smoothstep(0.62, 0.7, band) * (1.0 - smoothstep(0.88, 0.95, band));
	}
	if (kind == 2) {  // polka dots
		vec3 cell = fract(q) - 0.5;
		return 1.0 - smoothstep(0.24, 0.3, length(cell));
	}
	if (kind == 3) {  // camo: two blotch layers
		float a = pat_noise(q * 0.8);
		float b = pat_noise(q * 1.6 + 11.0);
		return max(step(0.55, a) * 0.65, step(0.62, b));
	}
	if (kind == 4) {  // checker
		vec3 c = floor(q);
		return mod(c.x + c.y + c.z, 2.0);
	}
	if (kind == 5) {  // zebra: bold vertical stripes, bent by noise
		float band = fract(q.x * 0.9 + q.z * 0.4 + pat_noise(q * 0.9) * 0.9);
		return step(0.55, band);
	}
	if (kind == 6) {  // galaxy: swirls and stars
		float swirl = pat_noise(q * 0.6 + vec3(0.0, q.x * 0.2, 0.0));
		sparkle = step(0.965, pat_hash(q * 4.0)) * step(0.4, pat_noise(q * 2.0));
		return smoothstep(0.45, 0.75, swirl);
	}
	if (kind == 7) {  // waves
		float w = sin(q.y * 6.2831 + sin(q.x * 3.1 + q.z * 2.0) * 1.2);
		return smoothstep(0.55, 0.75, w);
	}
	return 0.0;
}
