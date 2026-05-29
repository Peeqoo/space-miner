shader_type canvas_item;

uniform vec2 light_direction = vec2(-1.0, -0.25);
uniform float light_height : hint_range(0.05, 1.0) = 0.35;

uniform float shadow_strength : hint_range(0.0, 1.0) = 0.55;
uniform float light_boost : hint_range(0.0, 1.0) = 0.12;
uniform float terminator_softness : hint_range(0.01, 0.8) = 0.18;

uniform vec4 shadow_tint : source_color = vec4(0.08, 0.11, 0.20, 1.0);
uniform vec4 light_tint : source_color = vec4(1.0, 0.92, 0.72, 1.0);

uniform float rim_strength : hint_range(0.0, 1.0) = 0.08;
uniform float rim_power : hint_range(1.0, 12.0) = 4.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	if (tex.a <= 0.01) {
		COLOR = tex;
	} else {
		vec2 p = UV * 2.0 - 1.0;
		float radius_sq = dot(p, p);
		float z = sqrt(max(0.0, 1.0 - min(radius_sq, 1.0)));

		vec3 normal = normalize(vec3(p.x, -p.y, z));

		vec2 safe_light_direction = light_direction;
		if (length(safe_light_direction) <= 0.0001) {
			safe_light_direction = vec2(-1.0, -0.25);
		}

		vec2 dir2 = normalize(safe_light_direction);
		vec3 light_vec = normalize(vec3(dir2.x, -dir2.y, light_height));

		float ndotl = dot(normal, light_vec);
		float lit = smoothstep(-terminator_softness, terminator_softness, ndotl);

		vec3 shadowed = mix(tex.rgb, tex.rgb * shadow_tint.rgb, shadow_strength);
		vec3 lit_color = tex.rgb * light_tint.rgb + tex.rgb * light_boost;

		vec3 final_color = mix(shadowed, lit_color, lit);

		float rim = pow(clamp(1.0 - z, 0.0, 1.0), rim_power) * rim_strength * lit;
		final_color += light_tint.rgb * rim;

		COLOR = vec4(final_color, tex.a);
	}
}