#if defined(VERTEX)
precision mediump float;

layout(std140) uniform PerFrameData {
    mat4 MVP;
    mat4 invVPMat;
};

////////////

out vec4 pos;
out vec4 worldPos;

void main() {
    const vec4 gridPoints = vec4(-1, -1, 1, 1);

    ivec2 i = ivec2(gl_VertexID & 2, (gl_VertexID << 1 & 2) ^ 3);

    gl_Position = vec4(gridPoints[i.x], gridPoints[i.y], 0.0, 1.0);
    // vsOut.clipPos = vec2(gridPoints[i.x], gridPoints[i.y]);

    worldPos = invVPMat * vec4(gridPoints[i.x], gridPoints[i.y], 0.0, 1.0);
    worldPos.xyz /= worldPos.w;
}

#elif defined(FRAGMENT)
precision mediump float;

in vec4 worldPos;

out vec4 FragColor;

void main() {
    const float lineSize = 1.0;

    vec2 deriv = fwidth(worldPos.xy);
    vec2 grid = abs(fract(worldPos.xy - 0.5) - 0.5) / deriv;
    float l = min(grid.x, grid.y);

    // float4 col = float4(0.1, 0.1, 0.1, step(l, lineSize));
    vec4 col = vec4(0.1, 0.1, 0.1, 1.0 - min(l, 1.0));

    deriv.x = min(deriv.x, 1.0);
    deriv.y = min(deriv.y, 1.0);

    if(worldPos.x > -deriv.x && worldPos.x < deriv.x) {
        col.x = 1.0;
    }
    if(worldPos.y > -deriv.y && worldPos.y < deriv.y) {
        col.y = 1.0;
    }

    FragColor = col;
}

#endif