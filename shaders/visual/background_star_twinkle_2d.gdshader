shader_type canvas_item;

uniform float glow_strength : hint_range(0.0, 1.0) = 0.08;
uniform float twinkle_strength : hint_range(0.0, 0.3) = 0.04;
uniform float twinkle_speed : hint_range(0.0, 5.0) = 0.45;
uniform float star_threshold : hint_range(0.0, 1.0) = 0.55;
uniform vec4 glow_tint : source_color = vec4(0.86, 0.92, 1.0, 1.0);

float random_value(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	float brightness = max(max(tex.r, tex.g), tex.b);
	float star_mask = smoothstep(star_threshold, 1.0, brightness) * tex.a;

	float noise = random_value(floor(UV * 900.0));
	float twinkle = sin(TIME * twinkle_speed + noise * 6.2831853) * 0.5 + 0.5;
	float twinkle_amount = twinkle * twinkle_strength;

	vec3 boosted = tex.rgb + glow_tint.rgb * star_mask * (glow_strength + twinkle_amount);

	COLOR = vec4(boosted, tex.a);
}