// Shop / starter cards (ParallaxCard): the card picture drawn as a real tilted plane in perspective
// (per pixel, so there is no seam), with a glare band that slides over it as it turns.
shader_type canvas_item;

uniform float yaw = 0.0;        // radians, turn around the vertical axis (mouse x)
uniform float pitch = 0.0;      // radians, turn around the horizontal axis (mouse y)
uniform float distance = 2.6;   // eye distance in half-card heights: smaller = stronger perspective
uniform float inset = 0.9;      // the card fills this much of the rect (room to turn)
uniform float aspect = 0.72;    // width / height of the card
uniform float glare = 0.35;
uniform float lift = 0.0;       // 0..1 hover: brighter edge
uniform float corner = 0.1;     // corner radius in half-card heights (the frame's radius)

mat3 rot() {
	float cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch);
	mat3 ry = mat3(vec3(cy, 0.0, -sy), vec3(0.0, 1.0, 0.0), vec3(sy, 0.0, cy));
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cp, sp), vec3(0.0, -sp, cp));
	return ry * rx;
}

// The node's modulate (in fragment() COLOR already holds the untilted texture)
varying vec4 tint;
void vertex() {
	tint = COLOR;
}

void fragment() {
	// Screen point in card units: x in [-aspect, aspect], y in [-1, 1] (y down like UV)
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
	// Rounded corners: the background layers are plain rectangles, cut them along the frame
	vec2 q = abs(local.xy) - vec2(aspect, 1.0) + corner;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
	float aa = max(fwidth(d), 0.0001);
	c.a *= 1.0 - smoothstep(-aa, aa * 0.5, d);
	// Glare: a soft diagonal band that follows the tilt
	float band = uv.x * 0.8 + uv.y * 0.6 - 0.7 + yaw * 1.8 - pitch * 1.4;
	float shine = exp(-band * band * 18.0) * glare * (0.35 + lift);
	c.rgb += vec3(1.0, 0.97, 0.9) * shine * c.a;
	COLOR = c * tint;
}
