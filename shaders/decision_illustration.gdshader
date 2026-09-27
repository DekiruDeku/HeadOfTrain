shader_type canvas_item;
// Soft print edges merge the supplied artwork into the paper underneath.
void fragment() {
    float sides = smoothstep(0.0, 0.01, UV.x) * smoothstep(0.0, 0.01, 1.0 - UV.x);
    float top = smoothstep(0.0, 0.022, UV.y);
    float bottom = smoothstep(0.0, 0.13, 1.0 - UV.y);
    COLOR.a *= sides * top * bottom;
}
