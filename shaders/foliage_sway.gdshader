// Biome decor (BiomeDecor): tall grass, flowers, thorns. Instance colors from the MultiMesh, the
// top of each blade sways in a slow wind that rolls across the map (world-space phase).
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform float sway = 0.12;        // metres at the top of a 1 m blade
uniform float emission = 0.0;     // mushroom caps glow a little

varying vec3 tint;
varying float height;

void vertex() {
	tint = pow(COLOR.rgb, vec3(2.2));  // instance colors come in sRGB
	height = VERTEX.y;
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = TIME * 1.6 + world.x * 0.35 + world.z * 0.22;
	float bend = max(VERTEX.y, 0.0);
	VERTEX.x += sin(phase) * sway * bend * bend;
	VERTEX.z += cos(phase * 0.8) * sway * 0.6 * bend * bend;
}

void fragment() {
	// Thin blades are lit the same from both sides (Godot flips back-face normals: undo it)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = tint;
	ROUGHNESS = 0.8;
	EMISSION = tint * emission;
	// Darker towards the ground: reads as depth from above
	ALBEDO *= mix(0.6, 1.0, clamp(height / 0.8, 0.0, 1.0));
}
