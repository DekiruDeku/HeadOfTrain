shader_type canvas_item;
uniform float travel = 0.0;
void fragment() {
    vec2 uv = UV * vec2(1.0, 0.66) + vec2(travel, -travel * 0.51);
    uv = vec2(1.0) - abs(mod(uv, vec2(2.0)) - vec2(1.0));
    vec4 c = texture(TEXTURE, uv);
    c.rgb = mix(c.rgb, vec3(0.29, 0.34, 0.25), 0.08);
    COLOR = c;
}
