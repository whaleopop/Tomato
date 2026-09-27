shader_type spatial;
render_mode blend_add, depth_draw_never, unshaded;

uniform vec3 glow_color : source_color = vec3(1.0, 0.6, 0.2);
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float fresnel_power : hint_range(0.5, 5.0) = 2.0;
uniform float base_intensity : hint_range(0.0, 2.0) = 0.5;

void fragment() {
	// Fresnel effect - stronger glow at edges
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);

	// Pulsing animation
	float pulse = (sin(TIME * pulse_speed) + 1.0) * 0.5;
	float intensity = base_intensity + pulse * pulse_intensity;

	// Final color with fresnel and pulse
	ALBEDO = glow_color * intensity;
	ALPHA = fresnel * (0.5 + pulse * 0.3);
}
