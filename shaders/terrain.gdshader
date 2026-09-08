shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Ландшафт без единой текстуры: цвет и рельеф поверхности считаются процедурно.
// Причина прозаическая — на большой карте текстурные швы и повторы видны
// сильнее, чем отсутствие фотодеталей, а память под мегатекстуру нужна живая.
//
// Цвет вершины несёт веса покрытий: R — песок, G — камень и хамада, B — накатка.
// Их же выдаёт TerrainField.surface_weights, поэтому граница песка на экране
// совпадает с границей песка в физике.

uniform vec3 sand_colour : source_color = vec3(0.80, 0.67, 0.45);
uniform vec3 sand_shadow : source_color = vec3(0.52, 0.40, 0.26);
uniform vec3 rock_colour : source_color = vec3(0.44, 0.40, 0.35);
uniform vec3 gravel_colour : source_color = vec3(0.58, 0.52, 0.43);
uniform vec3 track_colour : source_color = vec3(0.63, 0.56, 0.44);

// Направление господствующего ветра. По нему выстраивается рябь на песке —
// та самая, из-за которой дюны читаются как поверхность, а не как заливка.
uniform vec2 wind_direction = vec2(0.81, 0.58);
uniform float ripple_length = 1.5;
uniform float ripple_strength = 0.35;
uniform float macro_variation = 0.18;
uniform float sand_roughness = 0.62;
uniform float rock_roughness = 0.92;
// Насколько сильно песок бликует на солнце под скользящим углом.
uniform float sand_sheen = 0.35;

varying vec3 world_position;
varying vec3 surface_blend;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return total;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface_blend = COLOR.rgb;
}

void fragment() {
	vec2 p = world_position.xz;
	vec3 blend = normalize(max(surface_blend, vec3(0.001)));
	blend /= (blend.r + blend.g + blend.b);

	// Крупные пятна: где песок светлее, где темнее. Без них дюна — плоская
	// заливка, и глаз не понимает её формы даже при верном освещении.
	float macro = fbm(p * 0.012);
	float grain = fbm(p * 0.9);

	// Рябь: поперёк ветра, с плавающей фазой, чтобы не читалась решётка.
	float phase = dot(p, normalize(wind_direction)) / ripple_length;
	phase += fbm(p * 0.03) * 4.0;
	float ripple = sin(phase * 6.2831853);
	// Асимметрия ряби повторяет асимметрию дюн: пологий подъём, резкий срыв.
	ripple = sign(ripple) * pow(abs(ripple), 0.7);

	vec3 sand = mix(sand_shadow, sand_colour, clamp(0.45 + macro * macro_variation * 4.0, 0.0, 1.0));
	sand = mix(sand, sand * 1.08, ripple * 0.5 + 0.5);
	vec3 hard = mix(gravel_colour, rock_colour, clamp(grain * 1.4 - 0.15, 0.0, 1.0));

	vec3 albedo = sand * blend.r + hard * blend.g + track_colour * blend.b;
	// Накатка темнее и ровнее вокруг колеи — след от прошедших машин.
	albedo *= 1.0 - blend.b * 0.10;
	albedo *= 0.92 + grain * 0.16;

	ALBEDO = albedo;
	ROUGHNESS = mix(sand_roughness, rock_roughness, blend.g) - blend.r * ripple * 0.05;
	SPECULAR = 0.5 * (1.0 - blend.g * 0.4);
	METALLIC = 0.0;

	// Возмущение нормали от ряби и зерна. Дешевле карты нормалей и не даёт
	// повторов на километровых расстояниях.
	float dx = (fbm(p * 0.9 + vec2(0.35, 0.0)) - grain) * 2.4;
	float dz = (fbm(p * 0.9 + vec2(0.0, 0.35)) - grain) * 2.4;
	vec2 ripple_dir = normalize(wind_direction);
	float ripple_slope = cos(phase * 6.2831853) * ripple_strength * blend.r;
	vec3 bump = vec3(dx * 0.35 + ripple_dir.x * ripple_slope, 1.0, dz * 0.35 + ripple_dir.y * ripple_slope);
	NORMAL = normalize(mix(NORMAL, normalize((VIEW_MATRIX * vec4(normalize(bump), 0.0)).xyz), 0.35));

	// Скользящий блик: сухой песок под низким солнцем светится вдоль дюны.
	float grazing = pow(1.0 - abs(dot(normalize(VIEW), NORMAL)), 4.0);
	ALBEDO += vec3(0.9, 0.82, 0.66) * grazing * sand_sheen * blend.r * 0.25;
}
