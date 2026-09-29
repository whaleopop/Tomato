// Tree canopies (GardenTree): soft leafy shading, a gentle sway, and a dithered hole around the
// local hero (global "hero_position", updated by Player) so you can always see yourself under a
// tree. Dithered, not transparent: it stays in the depth buffer the fog of war reads.
shader_type spatial;
render_mode diffuse_burley;

uniform vec3 leaf_color : source_color = vec3(0.3, 0.58, 0.22);
uniform float fade_radius = 2.6;   // world units around the hero (horizontally)
global uniform vec3 hero_position;

varying vec3 world_pos;

float bayer(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = TIME * 1.1 + world_pos.x * 0.3 + world_pos.z * 0.2;
	VERTEX += NORMAL * sin(phase + VERTEX.y * 2.0) * 0.03;
}

void fragment() {
	float d = length(world_pos.xz - hero_position.xz);
	float above = step(hero_position.y + 0.5, world_pos.y);  // only what hangs over the hero
	float keep = mix(1.0, smoothstep(fade_radius * 0.55, fade_radius, d), above);
	if (keep < 0.98 && bayer(FRAGCOORD.xy) > keep * 0.85) {
		discard;
	}
	// Lighter on top (sun through leaves), darker underneath
	float up = clamp(dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz), -1.0, 1.0);
	ALBEDO = leaf_color * mix(0.72, 1.18, up * 0.5 + 0.5);
	ROUGHNESS = 0.9;
}
