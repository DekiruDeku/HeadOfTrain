shader_type canvas_item;
void fragment() {
    vec4 c = texture(TEXTURE, UV);
    float white = min(c.r, min(c.g, c.b));
    c.a *= 1.0 - smoothstep(0.90, 0.985, white);
    COLOR = c;
}
