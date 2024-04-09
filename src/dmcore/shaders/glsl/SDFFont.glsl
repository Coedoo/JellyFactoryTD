#if defined(VERTEX)
precision mediump float;

layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 aSize;
layout (location = 2) in vec2 aTexPos;
layout (location = 3) in vec2 aTexSize;
layout (location = 4) in vec4 aColor;


uniform vec2 OneOverAtlasSize;
uniform vec2 ScreenSize;

out vec2 uv;
out vec4 color;

void main() {
    // @ TODO: I can lower amount of buffers needed by 
    // combining those to rects:
    vec4 pos = vec4(aPos, aPos + aSize);
    vec4 texRect  = vec4(aTexPos, aTexPos + aTexSize);

    ivec2 i = ivec2(gl_VertexID & 2, (gl_VertexID << 1 & 2) ^ 3);

    gl_Position = vec4(vec2(pos[i.x], pos[i.y]) * ScreenSize - vec2(1, -1), 0, 1);
    uv = vec2(texRect[i.x], texRect[i.y]) * OneOverAtlasSize;

    color = aColor;
}

#elif defined(FRAGMENT)
precision mediump float;

in vec2 uv;
in vec4 color;

out vec4 FragColor;

uniform sampler2D tex;

void main() {
    const float edge = 128.0/255.0;
    const float aa = 16.0 / 255.0;

    float dist = texture(tex, uv).a;
    float alpha = smoothstep(edge - aa, edge + aa, dist);

    FragColor = vec4(color.rgb, alpha);
}

#endif