shader_type canvas_item;
// Static print grain belongs only to the paper, never to type or photographs.
void fragment() {
	float grain = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	COLOR.rgb *= 0.984 + grain * 0.032;
}
