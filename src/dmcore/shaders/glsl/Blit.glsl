#if defined(VERTEX)
precision mediump float;



////////////

out vec2 uv;

void main() {
    const vec4 pos = vec4(-1, -1, 1, 1);

    ivec2 i = ivec2(gl_VertexID & 2, (gl_VertexID << 1 & 2) ^ 3);
    gl_Position = vec4(pos[i.x], pos[i.y], 0.0, 1.0);

    vec4 tex = vec4(0.0, 0.0, 1.0, 1.0);
    uv = vec2(tex[i.x], tex[i.y]);
}

#elif defined(FRAGMENT)
precision mediump float;

in vec2 uv;

out vec4 FragColor;

uniform sampler2D tex;

void main() {
    vec4 col = texture(tex, uv);
    FragColor = col;
}

#endif