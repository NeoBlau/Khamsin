shader_type sky;

// Небо пустыни. Отличается от обычного тем, что в воздухе всегда висит пыль:
// у горизонта цвет уходит не в голубизну, а в охру, и чем сильнее ветер, тем
// выше поднимается эта полоса. В бурю она съедает небо целиком.

uniform vec3 zenith_day : source_color = vec3(0.16, 0.33, 0.62);
uniform vec3 horizon_day : source_color = vec3(0.72, 0.68, 0.55);
uniform vec3 zenith_night : source_color = vec3(0.020, 0.028, 0.055);
uniform vec3 horizon_night : source_color = vec3(0.075, 0.075, 0.10);
uniform vec3 dust_colour : source_color = vec3(0.68, 0.55, 0.36);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.86, 0.66);

// 0 — глухая ночь, 1 — полдень. Ставится контроллером неба по времени суток.
uniform float day_factor = 1.0;
// 0 — чистый воздух, 1 — стена песка.
uniform float dust = 0.15;
uniform float sun_size = 0.024;
uniform float sun_glow = 0.35;
uniform float star_intensity = 0.6;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	float height = clamp(EYEDIR.y, -1.0, 1.0);
	float up = clamp(height, 0.0, 1.0);

	vec3 zenith = mix(zenith_night, zenith_day, day_factor);
	vec3 horizon = mix(horizon_night, horizon_day, day_factor);
	vec3 colour = mix(horizon, zenith, pow(up, 0.42));

	// Звёзды: только ночью и только выше горизонта. Дешёвый хеш по направлению
	// взгляда — никаких текстур, а на глаз неотличимо.
	if (day_factor < 0.35 && height > 0.0) {
		vec3 cell = floor(EYEDIR * 320.0);
		float star = hash31(cell);
		float brightness = smoothstep(0.9975, 1.0, star) * (1.0 - day_factor / 0.35);
		colour += vec3(0.85, 0.88, 1.0) * brightness * star_intensity * up;
	}

	// Солнце и его ореол. Диск не рисуем в бурю: его там и не видно.
	float sun_dot = dot(EYEDIR, LIGHT0_DIRECTION);
	float disc = smoothstep(cos(sun_size * (1.0 + dust * 6.0)), 1.0, sun_dot);
	float glow = pow(max(sun_dot, 0.0), mix(180.0, 8.0, dust));
	colour += sun_tint * disc * LIGHT0_ENERGY * (1.0 - dust * 0.85) * 12.0;
	colour += sun_tint * glow * sun_glow * (0.35 + dust * 1.6);

	// Пыльная пелена: густеет к горизонту и поднимается с силой бури.
	float haze_height = mix(0.06, 1.4, dust);
	float haze = exp(-max(height, 0.0) / haze_height);
	haze = clamp(haze * (0.25 + dust * 1.5), 0.0, 1.0);
	vec3 lit_dust = dust_colour * mix(0.12, 1.0, day_factor);
	colour = mix(colour, lit_dust, haze);

	// Ниже горизонта — та же пыль, но темнее: там земля, а не небо.
	if (height < 0.0) {
		colour = mix(colour, lit_dust * 0.55, clamp(-height * 4.0, 0.0, 1.0));
	}

	COLOR = colour;
}
