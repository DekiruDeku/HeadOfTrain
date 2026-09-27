shader_type canvas_item;
// Subtle, stationary paper fibre; no texture files or animated noise.
void fragment() {
    vec2 p = FRAGCOORD.xy;
    float grain = fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
    COLOR.rgb += vec3((grain - 0.5) * 0.019);
}
