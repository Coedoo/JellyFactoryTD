cbuffer cameraConst : register(b0) {
    float4x4 VPMat;
}

cbuffer constants : register(b1) {
    float2 rn_screenSize;
    float2 oneOverAtlasSize;
}

/////////

struct sprite {
    float2 pos;
    float2 size;
    float rotation;
    int2 texPos;
    int2 texSize;
    float2 pivot;
    float4 color;
};

struct pixel {
    float4 pos: SV_POSITION;
    float2 uv: TEX;

    float4 color: COLOR;
};

//////////////

StructuredBuffer<sprite> spriteBuffer : register(t0);
Texture2D tex : register(t1);

SamplerState texSampler : register(s0);

////////////

pixel vs_main(uint spriteId: SV_INSTANCEID, uint vertexId : SV_VERTEXID) {
    sprite sp = spriteBuffer[spriteId];

    float2 anchor = sp.pivot * sp.size;
    anchor = float2(-anchor.x, anchor.y);
    float4 pos = float4(anchor, anchor + float2(sp.size.x, -sp.size.y));
    float4 tex = float4(sp.texPos + 0.5, sp.texPos + sp.texSize - 0.5);

    uint2 i = { vertexId & 2, (vertexId << 1 & 2) ^ 3 };

    pixel p;

    float2x2 rot = float2x2(cos(sp.rotation), -sin(sp.rotation), 
                            sin(sp.rotation), cos(sp.rotation));
    float2 tp = mul(rot, float2(pos[i.x], pos[i.y])) + sp.pos;

    p.pos = mul(VPMat, float4(tp, 0, 1));
    p.pos.xyz /= p.pos.w;
    // p.uv  = float2(tex[i.x], tex[i.y]) * oneOverAtlasSize;
    p.uv  = float2(tex[i.x], tex[i.y]);

    p.color = sp.color;

    return p;
}

float4 ps_main(pixel p) : SV_TARGET
{
    float2 uv = floor(p.uv) + smoothstep(0, 1, frac(p.uv) / fwidth(p.uv)) - 0.5;
    float4 texColor = tex.Sample(texSampler, uv * oneOverAtlasSize);

    if (texColor.a == 0) discard;

    // float4 c = float4(color.rgb * p.color.rgb, 1);
    // return c;

    return p.color * texColor;
}