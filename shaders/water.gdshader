shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// One shared material for every water tile (ShaderHelper.create_water_material), so the whole
// lake is one continuous surface:
//  - small waves from a few wind-driven wave trains + noise, all in world space (no seams)
//  - reflections: glossy surface (sky + screen-space reflections) with a fresnel sky tint
//  - foam along the shore only (edges whose neighbour is land / void, see HexTile.update_edges)
//  - ripples where players wade through (WaterRipples uploads them each frame)
//  - shallow water is lighter and blends into deep water across the tile border
// Opaque: the old transparency only ever showed the dark abyss under the tile, and the fog of
// war needs the water in the depth buffer.

uniform vec3 shallow_color : source_color = vec3(0.22, 0.62, 0.78);
uniform vec3 deep_color : source_color = vec3(0.07, 0.25, 0.48);
uniform vec3 sky_color : source_color = vec3(0.62, 0.78, 0.95);
uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 1.0);

uniform float wave_speed : hint_range(0.1, 5.0) = 1.0;
uniform float wave_height : hint_range(0.0, 0.2) = 0.025;   // vertex bob: small, the shore must meet
uniform float wave_frequency : hint_range(0.5, 10.0) = 3.0;
uniform float ripple_strength : hint_range(0.0, 3.0) = 1.0;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.6;
uniform float water_clarity : hint_range(0.0, 1.0) = 0.7;
uniform float surface_drop : hint_range(0.0, 0.1) = 0.04;  // a little below the shore: a bank, wading feet

// Kept for compatibility with older materials
uniform sampler2D wave_noise : hint_default_white;
uniform sampler2D foam_noise : hint_default_white;
uniform float foam_scale : hint_range(1.0, 20.0) = 5.0;

// Player ripples: xy = world xz, z = age (s), w = strength (0 = unused)
uniform vec4 ripples[16];
uniform int ripple_count = 0;
const float RIPPLE_SPEED = 1.6;

// Per tile: shallow (1) or deep (0); across each edge: a = 1 shore / void, r = neighbour shallow
instance uniform float shallow = 0.0;
instance uniform vec4 edge_0 = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 edge_1 = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 edge_2 = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 edge_3 = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 edge_4 = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 edge_5 = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec3 corner_a = vec3(0.0);  // shared corner heights, as in hex_tile.gdshader
instance uniform vec3 corner_b = vec3(0.0);

varying vec3 world_pos;
varying vec3 local_pos;

// Integer hash of a lattice cell. The old fract(p * big) hash gave the same cell different
// values depending on how the compiler folded `i + vec2(1, 0)`, which drew the noise grid as lines.
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

float corner_offset(vec3 v) {
	int i = int(mod(round((atan(v.z, v.x) - 0.5235988) / 1.0471976) + 6.0, 6.0));
	if (i < 3) return corner_a[i];
	return corner_b[i - 3];
}

vec4 edge_info(int k) {
	if (k == 0) return edge_0;
	if (k == 1) return edge_1;
	if (k == 2) return edge_2;
	if (k == 3) return edge_3;
	if (k == 4) return edge_4;
	return edge_5;
}

// Gentle swell (also moves the vertices a little)
float swell(vec2 p, float t) {
	vec2 uv = p * wave_frequency * 0.1;
	return (sin(uv.x + t) * cos(uv.y + t * 0.7) + sin(uv.x * 1.3 - t * 0.8) * cos(uv.y * 0.9 + t)) * 0.5;
}

// Surface detail for the normals: wind waves + noise chop + player ripples
float surface(vec2 p, float t) {
	float h = swell(p, t) * 0.03;
	h += sin(dot(p, vec2(0.8, 0.6)) * 3.1 + t * 2.1) * 0.012;
	h += sin(dot(p, vec2(-0.5, 0.9)) * 4.3 + t * 2.7) * 0.008;
	h += (noise(p * 2.2 + vec2(t * 0.35, t * 0.2)) - 0.5) * 0.03;
	h += (noise(p * 5.5 - vec2(t * 0.5, -t * 0.3)) - 0.5) * 0.012;
	for (int i = 0; i < ripple_count; i++) {
		vec4 r = ripples[i];
		float d = distance(p, r.xy);
		float front = r.z * RIPPLE_SPEED;
		// a short wave train just behind the expanding front
		float band = (1.0 - smoothstep(0.0, 0.45, abs(d - front + 0.22))) * smoothstep(0.0, 0.15, d);
		h += sin((d - front) * 16.0) * exp(-r.z * 1.5) * band * 0.05 * r.w * ripple_strength;
	}
	return h;
}

float ripple_foam(vec2 p) {
	float foam = 0.0;
	for (int i = 0; i < ripple_count; i++) {
		vec4 r = ripples[i];
		float d = distance(p, r.xy);
		float front = r.z * RIPPLE_SPEED;
		float fade = exp(-r.z * 1.7) * r.w;
		foam += (1.0 - smoothstep(0.0, 0.1, abs(d - front))) * fade;             // leading ring
		foam += (1.0 - smoothstep(0.0, 0.07, abs(d - front + 0.3))) * fade * 0.5;  // a fainter one behind
		foam += (1.0 - smoothstep(0.1, 0.4, d)) * exp(-r.z * 6.0) * r.w * 0.6;     // splash at the feet
	}
	return clamp(foam, 0.0, 1.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_pos = VERTEX;
	if (VERTEX.y > 0.0) {
		VERTEX.y += corner_offset(VERTEX) - surface_drop + swell(world_pos.xz, TIME * wave_speed) * wave_height;
	}
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = world_pos.xz;

	// Normal from the height field (world space -> view space)
	float e = 0.04;
	float h0 = surface(p, t);
	float hx = surface(p + vec2(e, 0.0), t);
	float hz = surface(p + vec2(0.0, e), t);
	vec3 n_world = normalize(vec3(-(hx - h0) / e * normal_strength, 1.0, -(hz - h0) / e * normal_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Depth color: shallow tiles lighter, blending into their neighbours at the border
	float shallow_amount = shallow;
	float shore = 0.0;
	for (int k = 0; k < 6; k++) {
		vec4 info = edge_info(k);
		float angle = 1.04719755 * float(k);
		float d = 0.8660254 - dot(local_pos.xz, vec2(cos(angle), sin(angle)));
		if (info.a > 0.5) {
			shore = max(shore, 1.0 - smoothstep(0.0, 0.32, d));
		} else {
			float w = 1.0 - smoothstep(0.0, 0.5, d);
			shallow_amount = mix(shallow_amount, (shallow + info.r) * 0.5, w * w);
		}
	}
	float swirl = noise(p * 0.35 + vec2(t * 0.05, 0.0));
	vec3 water = mix(deep_color, shallow_color, clamp(shallow_amount * 0.75 + shore * 0.35 + (swirl - 0.5) * 0.15, 0.0, 1.0));

	// Shore foam: broken, slowly pulsing line along the land
	float foam_noise_v = noise(p * 3.0 + vec2(t * 0.4, -t * 0.25));
	float pulse = 0.5 + 0.5 * sin(t * 1.5 + (p.x + p.y) * 0.7);
	float foam = shore * smoothstep(0.35, 0.75, foam_noise_v + shore * 0.35 * pulse) * foam_amount;
	foam = max(foam, ripple_foam(p) * 0.85 * ripple_strength);

	// Reflection tint: grazing views mirror the sky
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 color = mix(water, sky_color, clamp(fresnel * 0.65, 0.0, 0.6));
	color = mix(color, foam_color, foam);
	// Old "clarity" look: a touch of the dark abyss below
	color = mix(vec3(0.03, 0.06, 0.12), color, clamp(water_clarity + 0.25, 0.0, 1.0));

	ALBEDO = color;
	ROUGHNESS = mix(0.04, 0.5, foam);
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
