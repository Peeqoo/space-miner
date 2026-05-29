shader_type canvas_item;

uniform vec4 vignette_color : source_color = vec4(0.02, 0.03, 0.08, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.18;
uniform float radius : hint_range(0.0, 1.5) = 0.62;
uniform float softness : hint_range(0.01, 1.0) = 0.38;

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	float distance_from_center = length(centered_uv) * 1.41421356;

	float vignette = smoothstep(radius, radius + softness, distance_from_center);
	float alpha = vignette * strength;

	COLOR = vec4(vignette_color.rgb, alpha);
}
