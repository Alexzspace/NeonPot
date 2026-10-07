shader_type canvas_item;
uniform float preview_time = -1.0;

float glow(vec2 uv, vec2 center, vec2 stretch, float density) {
	return exp(-length((uv - center) * stretch) * density);
}

void fragment() {
	vec2 uv = UV;
	float clock = preview_time >= 0.0 ? preview_time : TIME;
	float t = clock * 0.48;
	vec2 rose_center = vec2(0.24 + sin(t * 0.82) * 0.22, 0.66 + cos(t * 0.66) * 0.25);
	vec2 cyan_center = vec2(0.76 + cos(t * 0.71 + 1.0) * 0.20, 0.30 + sin(t * 0.92) * 0.26);
	vec2 violet_center = vec2(0.48 + sin(t * 0.53 + 2.0) * 0.24, 0.50 + cos(t * 0.84) * 0.26);
	vec2 amber_center = vec2(0.85 + sin(t * 0.59) * 0.10, 0.81 + cos(t * 0.61) * 0.16);
	vec3 color = vec3(0.022, 0.025, 0.066);
	color += glow(uv, rose_center, vec2(1.65, 1.15), 3.5) * vec3(0.39, 0.038, 0.21) * (0.84 + 0.25 * sin(t * 1.8));
	color += glow(uv, cyan_center, vec2(1.6, 1.0), 3.7) * vec3(0.018, 0.22, 0.36) * (0.88 + 0.23 * sin(t * 1.45 + 2.0));
	color += glow(uv, violet_center, vec2(1.2, 1.4), 4.3) * vec3(0.22, 0.032, 0.32) * (0.85 + 0.22 * cos(t));
	color += glow(uv, amber_center, vec2(1.8, 1.35), 6.0) * vec3(0.24, 0.087, 0.035) * (0.8 + 0.25 * sin(t * 1.2));
	// Soft vertical reflections suggest neon streets without a literal skyline.
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float x = 0.1 + fi * 0.2 + sin(t * 0.36 + fi * 1.7) * 0.035;
		float streak = exp(-pow((uv.x - x) * 42.0, 2.0)) * pow(abs(uv.y - 0.5) * 2.0, 2.0);
		color += streak * mix(vec3(0.015, 0.075, 0.10), vec3(0.10, 0.012, 0.067), sin(fi * 2.3 + t) * 0.5 + 0.5);
	}
	vec2 p = floor(FRAGCOORD.xy / 2.0);
	float grain = fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
	COLOR = vec4(color + (grain - 0.5) * 0.009, 1.0);
}
