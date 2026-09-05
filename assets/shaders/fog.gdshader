shader_type canvas_item;

// Full-screen atmosphere pass: a vignette that crushes the edges toward black plus
// slow drifting fog banks, to keep the readable area around the player and let the
// rest of the room fall away into the dark.

uniform vec4 fog_color : source_color = vec4(0.06, 0.07, 0.09, 1.0);
uniform float fog_density : hint_range(0.0, 1.0) = 0.30;
uniform float vignette_strength : hint_range(0.0, 2.0) = 1.15;
uniform float vignette_softness : hint_range(0.05, 1.5) = 0.65;
uniform float drift_speed = 0.015;
uniform float fog_scale = 3.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		total += value_noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 uv = UV;

	// Two layers drifting at different rates so the banks never look like one sheet.
	float t = TIME * drift_speed;
	float bank = fbm(uv * fog_scale + vec2(t, t * 0.35));
	bank = mix(bank, fbm(uv * fog_scale * 1.7 - vec2(t * 1.6, 0.0)), 0.45);

	vec2 centered = (uv - 0.5) * vec2(1.0, 0.62);
	float vignette = smoothstep(vignette_softness, vignette_softness * 0.25, length(centered));
	float dark = (1.0 - vignette) * vignette_strength;

	float alpha = clamp(bank * fog_density + dark, 0.0, 1.0);
	COLOR = vec4(fog_color.rgb, alpha);
}
