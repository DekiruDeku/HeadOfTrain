shader_type canvas_item;
// Stationary paper grain, no temporal noise or flashing.
void fragment() {
	vec4 base = COLOR;
	float grain = fract(sin(dot(UV * vec2(1672.0, 941.0), vec2(12.9898, 78.233))) * 43758.5453);
	COLOR = vec4(base.rgb * (0.965 + grain * 0.055), base.a);
}
