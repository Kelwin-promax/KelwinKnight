shader_type canvas_item;

// Blends the sprite toward a flat colour without touching its silhouette, so a hit
// reads as a solid white cut-out for a frame or two.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = mix(tex, vec4(flash_color.rgb, tex.a), flash_amount * tex.a);
}
