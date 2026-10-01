shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.93, 0.74, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.14;

void fragment() {
	float side = smoothstep(0.0, 0.30, min(UV.x, 1.0 - UV.x));
	float fade = pow(clamp(1.0 - UV.y, 0.0, 1.0), 2.1);
	float a = side * fade * strength;
	ALBEDO = tint.rgb * a * 3.4;
	ALPHA = a;
}
