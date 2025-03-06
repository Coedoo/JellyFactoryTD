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
    mat4 invMVP;
    int screenSpace;
};

uniform vec2 ScreenSize;

out vec2 uv;
out vec4 color;

void main() {
    ivec2 i = ivec2(gl_VertexID & 2, (gl_VertexID << 1 & 2) ^ 3);

    vec2 anchor = aPivot * aSize;
    vec4 pos = vec4(
        0,
        aSize.y,
        aSize.x,
        0
    );

    vec2 vertexPos = vec2(pos[i.x], pos[i.y]) - anchor;
    mat2 rot = mat2(cos(aRot), sin(aRot),
                    -sin(aRot), cos(aRot));
    vec2 tp = rot * vertexPos + aPos;

    gl_Position = MVP * vec4(tp, 0, 1);

    // 0 - for world space (Y up)
    // 1 - for screen space (Y down)
    vec4 texUVS[2] = vec4[2](
        vec4(aTexPos, aTexPos + aTexSize),
        vec4(aTexPos.x, aTexPos.y + aTexSize.y, aTexPos.x + aTexSize.x, aTexPos.y)
    );

    vec4 tex = texUVS[screenSpace];
    uv = vec2(tex[i.x], tex[i.y]);

    color = aColor;
}

#elif defined(FRAGMENT)
precision mediump float;

uniform vec2 OneOverAtlasSize;

in vec2 uv;
in vec4 color;

out vec4 FragColor;

uniform sampler2D tex;

void main() {
    const float edge = 128.0/255.0;
    const float aa = 16.0 / 255.0;

    float dist = texture(tex, uv * OneOverAtlasSize).a;
    float alpha = smoothstep(edge - aa, edge + aa, dist);

    FragColor = vec4(color.rgb, alpha);
}

#endif