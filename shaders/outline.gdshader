shader_type spatial;
render_mode unshaded, cull_front;

// Outline parameters
uniform vec3 outline_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 0.1) = 0.02;
uniform float pulse_speed : hint_range(0.0, 5.0) = 0.0;
uniform float pulse_min : hint_range(0.0, 1.0) = 0.8;

void vertex() {
	// Expand vertices along normals
	float width = outline_width;

	// Optional pulse effect
	if (pulse_speed > 0.0) {
		float pulse = (sin(TIME * pulse_speed) + 1.0) * 0.5;
		width *= mix(pulse_min, 1.0, pulse);
	}

	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = outline_color;
	ALPHA = 1.0;
}
