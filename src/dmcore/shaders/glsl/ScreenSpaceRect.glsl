#if defined(VERTEX)
precision mediump float;

layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 aSize;
layout (location = 2) in vec2 aTexPos;
layout (location = 3) in vec2 aTexSize;
layout (location = 4) in vec4 aColor;

// layout(std140) uniform PerBatchData {
//     vec2 ScreenSize;
//     vec2 OneOverAtlasSize;
// };

uniform vec2 OneOverAtlasSize;
uniform vec2 ScreenSize;

out vec2 uv;
out vec4 color;

void main() {
    color = aColor;

    // @ TODO: I can lower amount of buffers needed by 
    // combining those to rects:
    vec4 pos = vec4(aPos, aPos + aSize);
    vec4 texRect  = vec4(aTexPos, aTexPos + aTexSize);

    ivec2 i = ivec2(gl_VertexID & 2, (gl_VertexID << 1 & 2) ^ 3);

    gl_Position = vec4(vec2(pos[i.x], pos[i.y]) * ScreenSize - vec2(1, -1), 0, 1);
    uv = vec2(texRect[i.x], texRect[i.y]) * OneOverAtlasSize;
}

#elif defined(FRAGMENT)
precision mediump float;

in vec2 uv;
in vec4 color;

out vec4 FragColor;

uniform sampler2D tex;

void main() {
    vec4 texColor = texture(tex, uv);

    // @TODO: check if it causes performance hit
    if(color.a == 0.) discard;

    vec3 c = color.rgb;
    FragColor = vec4(c, color.a) * texColor;
}

#endif