// Waterfalls (Waterfalls.gd). pool = 0: the falling ribbon - a clear turquoise core with white
// streaks racing down (UV.y runs along the fall), ragged, thinning sides, and foam where it hits
// the water. pool = 1: the churned foam ring at the foot (a flat plane, UV centered), rings
// spreading out and breaking up. Opaque (with ragged cut-outs): the fog of war reads the depth.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec3 water_color : source_color = vec3(0.4, 0.82, 0.9);
uniform vec3 deep_color : source_color = vec3(0.22, 0.6, 0.78);
uniform vec3 foam_color : source_color = vec3(0.96, 0.99, 1.0);
uniform float speed = 1.6;
uniform float pool = 0.0;

float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = (q.x * 1597334677u) ^ (q.y * 3812015801u);
	h = (h ^ (h >> 16u)) * 2246822519u;
	h ^= h >> 13u;
	return float(h) * (1.0 / 4294967295.0);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float t = TIME * speed;
	vec3 color;
	if (pool > 0.5) {
		// Foam ring: dense in the middle, broken rings travelling outwards
		vec2 c = (UV - 0.5) * 2.0;
		float r = length(c);
		float ang = atan(c.y, c.x);
		float n = noise(vec2(ang * 3.0, r * 4.0 - t * 1.2)) * 0.6 + noise(c * 6.0 + t * 0.5) * 0.4;
		float rings = smoothstep(0.55, 0.8, sin((r * 7.0 - t * 2.5) * 3.14159) * 0.5 + 0.5) * (1.0 - r);
		float foam = max(1.0 - smoothstep(0.1, 0.45, r), rings) * smoothstep(0.25, 0.6, n + (1.0 - r) * 0.4);
		if (foam < 0.35 || r > 0.95) {
			discard;
		}
		color = foam_color;
	} else {
		vec2 uv = UV;
		// Water speeds up as it falls: the streaks stretch lower down
		float v = uv.y * uv.y * 3.0 - t * 2.2;
		float streaks = noise(vec2(uv.x * 10.0, v * 2.0)) * 0.6 + noise(vec2(uv.x * 26.0, v * 4.0 + 7.0)) * 0.4;
		// Ragged edges that thin out towards the bottom, broken into drops at the very end
		float edge = min(uv.x, 1.0 - uv.x);
		float ragged = 0.05 + 0.18 * uv.y * noise(vec2(uv.y * 8.0 - t * 3.0, uv.x * 4.0));
		if (edge < ragged || (uv.y > 0.9 && noise(vec2(uv.x * 14.0, uv.y * 20.0 - t * 6.0)) < (uv.y - 0.9) * 6.0)) {
			discard;
		}
		float core = smoothstep(0.0, 0.35, edge);
		color = mix(water_color, deep_color, core * 0.35);
		float white = smoothstep(0.5, 0.8, streaks) * (0.45 + 0.55 * uv.y);
		white = max(white, (1.0 - core) * 0.35);            // bright rims
		white = max(white, smoothstep(0.78, 1.0, uv.y) * 0.9); // foam where it hits
		color = mix(color, foam_color, clamp(white, 0.0, 1.0));
	}
	ALBEDO = color;
	ROUGHNESS = 0.2;
	EMISSION = color * 0.1;
}
