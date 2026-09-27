shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 fog_color : source_color = vec3(0.05, 0.05, 0.1);
uniform vec3 base_color : source_color = vec3(0.3, 0.7, 0.25);
uniform float visibility : hint_range(0.0, 1.0) = 1.0;
uniform float edge_glow : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	// Смешиваем базовый цвет с туманом в зависимости от видимости
	vec3 final_color = mix(fog_color, base_color, visibility);

	// Добавляем свечение на границе видимости
	float glow_factor = edge_glow * (1.0 - visibility) * visibility * 4.0;
	final_color += vec3(0.15, 0.2, 0.35) * glow_factor;

	ALBEDO = final_color;
	ROUGHNESS = mix(0.3, 0.8, visibility);
	METALLIC = 0.0;
}