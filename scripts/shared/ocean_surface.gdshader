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

// Whirlpool uniforms.
uniform vec2 u_whirlpool_center = vec2(4000.0, 4000.0);
uniform float u_whirlpool_radius = 600.0;
uniform float u_whirlpool_core_radius = 40.0;
uniform float u_whirlpool_enabled = 0.0;

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
	// Keep an undistorted copy for whirlpool visuals.
	vec2 world_raw = world;
	vec2 wind = normalize(u_wind_dir);
	vec2 crosswind = vec2(-wind.y, wind.x);
	// Wrap time to prevent float precision degradation over long sessions.
	// 200s cycle covers all animation frequencies cleanly (all use sin/cos).
	float t = mod(u_time * u_time_scale, 200.0);

	// ── Whirlpool: compute distance/angle in undistorted space ──
	float whirl_strength = 0.0;
	float whirl_dist = 0.0;
	float whirl_angle = 0.0;
	float whirl_norm = 0.0;  // 0 at edge, 1 at center.
	if (u_whirlpool_enabled > 0.5) {
		vec2 to_center = world_raw - u_whirlpool_center;
		whirl_dist = length(to_center);
		whirl_angle = atan(to_center.y, to_center.x);
		if (whirl_dist < u_whirlpool_radius && whirl_dist > 0.1) {
			whirl_norm = 1.0 - whirl_dist / u_whirlpool_radius;
			whirl_strength = whirl_norm * whirl_norm;  // Quadratic ramp.
			// Fade swirl to zero in outer half for seamless edge.
			float swirl_fade = smoothstep(0.0, 0.5, whirl_norm);
			// Swirl UV distortion — rotate texture sampling coords (CW to match physics).
			float swirl_angle = -(whirl_strength * 4.0 + sin(t * 1.9) * 0.5) * swirl_fade;
			float ca = cos(swirl_angle);
			float sa = sin(swirl_angle);
			vec2 offset = world - u_whirlpool_center;
			world = u_whirlpool_center + vec2(offset.x * ca - offset.y * sa, offset.x * sa + offset.y * ca);
			// Radial compression.
			float compress = 1.0 - whirl_strength * 0.2 * swirl_fade;
			world = u_whirlpool_center + (world - u_whirlpool_center) * compress;
		}
	}

	// ── Base ocean color ──
	float edge_dist = min(min(world.x, world.y), min(u_map_size_world.x - world.x, u_map_size_world.y - world.y));
	float edge_mix = 1.0 - smoothstep(0.0, 260.0, edge_dist);
	vec3 sea = mix(u_shallow_color.rgb, u_deep_color.rgb, clamp(edge_mix, 0.0, 1.0));

	// ── Whirlpool water color changes (use undistorted distance) ──
	if (u_whirlpool_enabled > 0.5 && whirl_dist < u_whirlpool_radius) {
		// Deep dark water — gets much darker toward center.
		vec3 deep_abyss = vec3(0.02, 0.06, 0.14);
		float dark_blend = whirl_strength * 0.8;
		sea = mix(sea, deep_abyss, dark_blend);

		// Teal/green tint in the mid-zone — churning unsettled water.
		float mid_zone = smoothstep(0.0, 0.4, whirl_norm) * smoothstep(0.9, 0.6, whirl_norm);
		sea = mix(sea, vec3(0.06, 0.22, 0.28), mid_zone * 0.35);

		// Outer ring: visible boundary — slightly different hue.
		float outer_band = smoothstep(0.0, 0.15, whirl_norm) * smoothstep(0.25, 0.1, whirl_norm);
		sea = mix(sea, vec3(0.14, 0.32, 0.42), outer_band * 0.2);
	}

	// ── Normal ocean waves (use swirled coords for natural distortion) ──
	float swell_a = sin(dot(world, wind * 0.0054 + crosswind * 0.0015) + t * 0.22);
	float swell_b = sin(dot(world, wind * 0.0031 - crosswind * 0.0027) - t * 0.17);
	float swell_noise = noise(world * 0.007 + wind * t * 0.05);
	float swell = swell_a * 0.55 + swell_b * 0.45 + (swell_noise - 0.5) * 0.9;
	// Suppress normal waves inside whirlpool — the vortex dominates.
	float wave_suppress = 1.0 - whirl_strength * 0.7;
	sea += u_swell_color.rgb * swell * (0.45 + u_swell_color.a) * wave_suppress;

	float ripple_noise = noise(world * 0.032 + wind * t * 0.55 + crosswind * sin(t * 0.2));
	float ripple_noise_2 = noise(world * 0.052 - wind * t * 0.42 + crosswind * 7.3);
	float ripple = (ripple_noise - 0.5) * 0.8 + (ripple_noise_2 - 0.5) * 0.5;
	sea += u_ripple_color.rgb * ripple * 0.20 * wave_suppress;

	// ── Whirlpool visual effects (all based on undistorted coords) ──
	if (u_whirlpool_enabled > 0.5 && whirl_strength > 0.005) {
		float r = whirl_dist;
		float a = whirl_angle;

		// Dark eye at the very center.
		float eye = smoothstep(u_whirlpool_core_radius * 1.2, u_whirlpool_core_radius * 0.3, r);
		sea = mix(sea, vec3(0.01, 0.03, 0.08), eye * 0.9);
	}

	// ── Normal wind streaks (suppressed inside whirlpool) ──
	float streak_phase = dot(world, wind * 0.028) + ripple_noise * 1.4 - t * 0.75;
	float streaks = smoothstep(0.64, 1.0, sin(streak_phase) * 0.5 + 0.5);
	sea += u_ripple_color.rgb * streaks * (0.05 + edge_mix * 0.02) * wave_suppress;

	float horizon = smoothstep(0.0, u_viewport_size.y, screen_px.y);
	vec3 sky_reflect = mix(u_sky_color.rgb * 0.14, u_sky_color.rgb * 0.03, horizon);
	sea += sky_reflect;

	COLOR = vec4(clamp(sea, 0.0, 1.0), 1.0);
}
