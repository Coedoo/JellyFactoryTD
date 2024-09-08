cbuffer cameraConst : register(b0) {
    float4x4 VPMat;
    float4x4 invVPMat;
}

////////////


struct VsOut {
    float4 pos: SV_POSITION;
    // float2 clipPos: CPOS;
    float4 worldPos: WPOS;
};

VsOut vs_main(uint spriteId: SV_INSTANCEID, uint vertexId : SV_VERTEXID) {
    static const float4 gridPoints = float4(-1, -1, 1, 1);

    uint2 i = { vertexId & 2, (vertexId << 1 & 2) ^ 3 };

    VsOut vsOut;
    vsOut.pos = float4(gridPoints[i.x], gridPoints[i.y], 0, 1);
    // vsOut.clipPos = float2(gridPoints[i.x], gridPoints[i.y]);

    vsOut.worldPos = mul(invVPMat, float4(gridPoints[i.x], gridPoints[i.y], 0, 1));
    vsOut.worldPos.xyz /= vsOut.worldPos.w;

    return vsOut;
}

float4 ps_main(VsOut vsOut) : SV_TARGET
{
    const float lineSize = 1;

    float2 deriv = fwidth(vsOut.worldPos.xy);
    float2 grid = abs(frac(vsOut.worldPos.xy - 0.5) - 0.5) / deriv;
    float l = min(grid.x, grid.y);

    // float4 col = float4(0.1, 0.1, 0.1, step(l, lineSize));
    float4 col = float4(0.1, 0.1, 0.1, 1.0 - min(l, 1.0));

    deriv.x = min(deriv.x, 1);
    deriv.y = min(deriv.y, 1);

    if(vsOut.worldPos.x > -deriv.x && vsOut.worldPos.x < deriv.x) {
        col.x = 1;
    }
    if(vsOut.worldPos.y > -deriv.y && vsOut.worldPos.y < deriv.y) {
        col.y = 1;
    }

    return col;
}