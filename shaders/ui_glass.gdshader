// Frosted glass for UI panels: blurs whatever was drawn behind the control.
// The control's StyleBoxFlat is used only as a mask (rounded corners + antialiasing via COLOR.a).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 7.0) = 3.2;
uniform vec4 tint_color : source_color = vec4(0.07, 0.09, 0.16, 0.42);
uniform float saturation : hint_range(0.0, 2.0) = 1.25;
uniform float brightness : hint_range(0.0, 2.0) = 1.05;

void fragment() {
	float mask = COLOR.a;

	// A few offset taps on the mip chain smooth out the blockiness of a single mip read
	vec2 spread = SCREEN_PIXEL_SIZE * exp2(blur_lod) * 0.6;
	vec3 bg = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb * 0.4;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(spread.x, spread.y), blur_lod).rgb * 0.15;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(-spread.x, spread.y), blur_lod).rgb * 0.15;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(spread.x, -spread.y), blur_lod).rgb * 0.15;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(-spread.x, -spread.y), blur_lod).rgb * 0.15;

	float luma = dot(bg, vec3(0.299, 0.587, 0.114));
	bg = mix(vec3(luma), bg, saturation) * brightness;
	bg = mix(bg, tint_color.rgb, tint_color.a);

	COLOR = vec4(bg, mask);
}
