// Weed Swarm perk cards (PerkCard): the card picture as a tilted plane in perspective like
// card_tilt.gdshader, plus a holographic foil - a rainbow sheen that runs over the card as it
// turns, fine diagonal foil lines, drifting scanlines and glitter - and a glowing rim.
shader_type canvas_item;

uniform float yaw = 0.0;
uniform float pitch = 0.0;
uniform float distance = 2.6;
uniform float inset = 0.9;
uniform float aspect = 0.7;
uniform float lift = 0.0;        // 0..1 hover
uniform float corner = 0.1;
uniform float foil = 0.3;        // strength of the rainbow
uniform vec4 rim_color : source_color = vec4(0.6, 0.9, 1.0, 1.0);
uniform float appear = 1.0;      // 0..1: the card materialises (scan from the top)

mat3 rot() {
	float cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch);
	mat3 ry = mat3(vec3(cy, 0.0, -sy), vec3(0.0, 1.0, 0.0), vec3(sy, 0.0, cy));
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cp, sp), vec3(0.0, -sp, cp));
	return ry * rx;
}

float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p))) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) * (1.0 / float(0xffffffffu));
}

// The node's modulate (in fragment() COLOR already holds the untilted texture)
varying vec4 tint;
void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 s = (UV - 0.5) * 2.0;
	s.x *= aspect;
	vec3 ro = vec3(0.0, 0.0, -distance);
	vec3 rd = normalize(vec3(s * inset, distance));
	mat3 r = rot();
	vec3 n = r * vec3(0.0, 0.0, 1.0);
	float t = -dot(ro, n) / dot(rd, n);
	vec3 hit = ro + rd * t;
	vec3 local = transpose(r) * hit;
	vec2 uv = vec2(local.x / aspect, local.y) * 0.5 + 0.5;
	if (t < 0.0 || uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		discard;
	}
	vec4 c = texture(TEXTURE, uv);
	vec2 q = abs(local.xy) - vec2(aspect, 1.0) + corner;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
	float aa = max(fwidth(d), 0.0001);
	c.a *= 1.0 - smoothstep(-aa, aa * 0.5, d);

	// Rainbow foil: the hue runs along the card diagonally and shifts with the tilt
	float hue = uv.x * 0.7 + uv.y * 0.45 + yaw * 2.2 - pitch * 1.6 + TIME * 0.04;
	vec3 rainbow = 0.5 + 0.5 * cos(6.2831 * (hue + vec3(0.0, 0.33, 0.67)));
	float lines = 0.55 + 0.45 * sin((uv.x + uv.y) * 260.0);
	float band = uv.x * 0.8 + uv.y * 0.6 - 0.7 + yaw * 1.8 - pitch * 1.4;
	float sheen = exp(-band * band * 6.0);
	float amount = foil * (0.45 + 0.9 * sheen) * (0.6 + 0.6 * lift) * lines;
	c.rgb = mix(c.rgb, c.rgb + rainbow * 0.9, amount * c.a);
	// Glare
	c.rgb += vec3(1.0, 0.97, 0.92) * exp(-band * band * 22.0) * 0.25 * (0.4 + lift) * c.a;
	// Scanlines drifting down
	c.rgb *= 0.94 + 0.06 * sin(uv.y * 520.0 - TIME * 6.0);
	// Glitter
	vec2 cell = uv * vec2(90.0, 128.0);
	float g = hash(cell);
	float tw = 0.5 + 0.5 * sin(TIME * 3.0 + g * 40.0 + yaw * 30.0);
	c.rgb += vec3(1.0) * step(0.985, g) * tw * 0.6 * (0.3 + lift) * c.a;
	// Glowing rim
	float rim = 1.0 - smoothstep(0.0, 0.035, -d);
	c.rgb = mix(c.rgb, rim_color.rgb * (1.2 + lift), rim * 0.8 * c.a);
	// Materialise: a bright scan line sweeps down, the card below it is not there yet
	float edge = appear * 1.1 - 0.05;
	float below = smoothstep(edge, edge + 0.02, uv.y);
	c.a *= 1.0 - below;
	c.rgb += rim_color.rgb * exp(-pow((uv.y - edge) * 40.0, 2.0)) * 1.5 * step(appear, 0.999);
	COLOR = c * tint;
}
