shader_type canvas_item;

uniform vec2 u_viewport_size = vec2(1280.0, 720.0);
uniform vec2 u_origin = vec2(0.0, 0.0);
uniform float u_world_scale = 1.0;
uniform vec2 u_map_size_world = vec2(8000.0, 8000.0);
uniform vec2 u_wind_dir = vec2(0.97, -0.24);
uniform float u_time_scale = 1.0;
uniform vec4 u_sky_color : source_color = vec4(0.40, 0.58, 0.78, 1.0);
uniform vec4 u_shallow_color : source_color = vec4(0.18, 0.44, 0.64, 1.0);
uniform vec4 u_deep_color : source_color = vec4(0.06, 0.22, 0.42, 1.0);
uniform vec4 u_swell_color : source_color = vec4(0.08, 0.18, 0.24, 0.18);
uniform vec4 u_ripple_color : source_color = vec4(0.74, 0.90, 0.98, 0.12);
uniform float u_time = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
	vec2 screen_px = UV * u_viewport_size;
	float world_scale = max(u_world_scale, 0.0001);
	vec2 world = (screen_px - u_origin) / world_scale;
	vec2 wind = normalize(u_wind_dir);
	vec2 crosswind = vec2(-wind.y, wind.x);
	float t = u_time * u_time_scale;

	float edge_dist = min(min(world.x, world.y), min(u_map_size_world.x - world.x, u_map_size_world.y - world.y));
	float edge_mix = 1.0 - smoothstep(0.0, 260.0, edge_dist);
	vec3 sea = mix(u_shallow_color.rgb, u_deep_color.rgb, clamp(edge_mix, 0.0, 1.0));

	float swell_a = sin(dot(world, wind * 0.0054 + crosswind * 0.0015) + t * 0.22);
	float swell_b = sin(dot(world, wind * 0.0031 - crosswind * 0.0027) - t * 0.17);
	float swell_noise = noise(world * 0.007 + wind * t * 0.05);
	float swell = swell_a * 0.55 + swell_b * 0.45 + (swell_noise - 0.5) * 0.9;
	sea += u_swell_color.rgb * swell * (0.45 + u_swell_color.a);

	float ripple_noise = noise(world * 0.032 + wind * t * 0.55 + crosswind * sin(t * 0.2));
	float ripple_noise_2 = noise(world * 0.052 - wind * t * 0.42 + crosswind * 7.3);
	float ripple = (ripple_noise - 0.5) * 0.8 + (ripple_noise_2 - 0.5) * 0.5;
	sea += u_ripple_color.rgb * ripple * 0.20;

	float streak_phase = dot(world, wind * 0.028) + ripple_noise * 1.4 - t * 0.75;
	float streaks = smoothstep(0.64, 1.0, sin(streak_phase) * 0.5 + 0.5);
	sea += u_ripple_color.rgb * streaks * (0.05 + edge_mix * 0.02);

	float horizon = smoothstep(0.0, u_viewport_size.y, screen_px.y);
	vec3 sky_reflect = mix(u_sky_color.rgb * 0.14, u_sky_color.rgb * 0.03, horizon);
	sea += sky_reflect;

	COLOR = vec4(clamp(sea, 0.0, 1.0), 1.0);
}
