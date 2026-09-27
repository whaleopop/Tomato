shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Seamless ground: neighbouring tiles of the same kind and height melt into one surface.
// HexTile.update_edges tells every tile what lies across each of its six edges
// (edge k faces 60 * k degrees in the XZ plane):
//   rgb = the neighbour's ground color, a = 0: same level -> colors blend into each other
//                                         a = 1: step / water / void -> a darker rim
// At an edge both tiles compute the same average, so there is no line between them.
// corner_a / corner_b move the six top corners to the height the joined tiles share there,
// so small height differences don't leave steps either.

// Tile properties
uniform vec3 tile_color : source_color = vec3(0.3, 0.7, 0.25);
uniform float tile_height : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width : hint_range(0.0, 0.2) = 0.05;
uniform vec3 edge_color : source_color = vec3(0.15, 0.35, 0.12);
uniform float blend_width : hint_range(0.05, 0.8) = 0.42;  // how far two biomes fade into each other
uniform float rim_width : hint_range(0.01, 0.3) = 0.1;     // dark rim on steps and cliffs

// Effects
uniform float damage_amount : hint_range(0.0, 1.0) = 0.0;
uniform float hover_highlight : hint_range(0.0, 1.0) = 0.0;
uniform float destruction_progress : hint_range(0.0, 1.0) = 0.0;

// Noise for variation
uniform sampler2D noise_texture : hint_default_white;
uniform float noise_scale : hint_range(0.1, 10.0) = 2.0;
uniform float noise_strength : hint_range(0.0, 0.5) = 0.1;
uniform float patch_strength : hint_range(0.0, 0.4) = 0.12;  // large soft patches across tiles

instance uniform vec4 edge_0 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 edge_1 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 edge_2 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 edge_3 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 edge_4 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 edge_5 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec3 corner_a = vec3(0.0);  // corners 0-2 (at 30, 90, 150 degrees)
instance uniform vec3 corner_b = vec3(0.0);  // corners 3-5

varying vec3 world_position;
varying vec3 local_position;

// Integer hash of a lattice cell. The old fract(p * big) hash gave the same cell different
// values depending on how the compiler folded `i + vec2(1, 0)`, which drew the noise grid as lines.
float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = (q.x * 1597334677u) ^ (q.y * 3812015801u);
	h = (h ^ (h >> 16u)) * 2246822519u;
	h ^= h >> 13u;
	return float(h) * (1.0 / 4294967295.0);
}

float value_noise(vec2 p) {
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

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_position = VERTEX;
	if (VERTEX.y > 0.0) {
		VERTEX.y += corner_offset(VERTEX);  // the side faces share these vertices, so they follow
	}

	// Destruction animation - sink and scale down
	if (destruction_progress > 0.0) {
		VERTEX.y -= destruction_progress * 2.0;
		VERTEX.xz *= 1.0 - destruction_progress * 0.5;
	}
}

void fragment() {
	// 1) base color, blended with same-level neighbours towards the shared edge
	vec3 base = tile_color;
	float rim = 0.0;
	vec2 p = local_position.xz;
	for (int k = 0; k < 6; k++) {
		vec4 e = edge_info(k);
		float angle = 1.04719755 * float(k);
		float d = 0.8660254 - dot(p, vec2(cos(angle), sin(angle)));  // distance to edge k
		if (e.a > 0.5) {
			rim = max(rim, 1.0 - smoothstep(0.0, rim_width, d));
		} else {
			float w = 1.0 - smoothstep(0.0, blend_width, d);
			base = mix(base, (tile_color + e.rgb) * 0.5, w * w * 0.999);
		}
	}

	// 2) variation in world space: continuous over tile borders
	vec2 noise_uv = world_position.xz * noise_scale * 0.1;
	float noise_value = texture(noise_texture, noise_uv).r;
	vec3 color = base + (noise_value - 0.5) * noise_strength;
	float patches = value_noise(world_position.xz * 0.18) * 0.65 + value_noise(world_position.xz * 0.55 + 7.3) * 0.35;
	color *= 1.0 + (patches - 0.5) * 2.0 * patch_strength;

	// 3) rims only where the ground really changes (steps, water, void)
	color = mix(color, edge_color, rim * 0.55);

	// Top face highlighting (sides of raised tiles are darker)
	float top_factor = smoothstep(0.0, 0.1, local_position.y);
	color = mix(color * 0.8, color, top_factor);

	// Damage effect - redden and darken
	if (damage_amount > 0.0) {
		vec3 damage_color = vec3(0.8, 0.2, 0.1);
		color = mix(color, damage_color, damage_amount * 0.5);
	}

	// Hover highlight
	if (hover_highlight > 0.0) {
		color += vec3(0.2) * hover_highlight;
	}

	// Opaque on purpose: writing ALPHA (it was always 1) put all 1261 tiles into the sorted
	// transparent pass, with no depth prepass - the fog of war reads that depth buffer.
	// Destroyed tiles shrink via the node scale (HexTile.destroy).
	ALBEDO = color;
	ROUGHNESS = 0.8;
	METALLIC = 0.0;
}
