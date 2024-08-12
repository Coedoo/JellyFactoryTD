#if defined(VERTEX)
precision mediump float;

layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 aSize;
layout (location = 2) in vec2 aTexPos;
layout (location = 3) in vec2 aTexSize;
layout (location = 4) in vec4 aColor;
layout (location = 5) in float aRot;
layout (location = 6) in vec2 aPivot;

layout(std140) uniform PerFrameData {
    mat4 MVP;
};

uniform vec2 OneOverAtlasSize;
uniform vec2 ScreenSize;

out vec2 uv;
out vec4 color;

void main() {
    color = aColor;

    vec2 anchor = aPivot * aSize;
    anchor.x *= -1.0;

    // @ TODO: I can lower amount of buffers needed by 
    // combining those to rects:
    vec4 pos = vec4(anchor, anchor + vec2(aSize.x, -aSize.y));
    vec4 texRect  = vec4(aTexPos + 0.5, aTexPos + aTexSize - 0.5);

    ivec2 i = ivec2(gl_VertexID & 2, (gl_VertexID << 1 & 2) ^ 3);

    mat2 rot = mat2(cos(aRot), sin(aRot),
                    -sin(aRot), cos(aRot));
    vec2 tp = rot * vec2(pos[i.x], pos[i.y]) + aPos;

    gl_Position = MVP * vec4(tp, 0, 1);
    // uv = vec2(texRect[i.x], texRect[i.y]) * OneOverAtlasSize;
    uv = vec2(texRect[i.x], texRect[i.y]);
}

#elif defined(FRAGMENT)
precision mediump float;

in vec2 uv;
in vec4 color;

out vec4 FragColor;

uniform sampler2D tex;
uniform vec2 OneOverAtlasSize;

void main() {
    vec2 fUV = floor(uv) + smoothstep(0.0, 1.0, fract(uv) / fwidth(uv)) - 0.5;
    vec4 texColor = texture(tex, fUV * OneOverAtlasSize);

    // @TODO: check if it causes performance hit
    if(color.a == 0.) discard;

    vec3 c = color.rgb * color.a;
    FragColor = vec4(c, color.a) * texColor;
    // FragColor = vec4(1,1,1,1);
}

#endif