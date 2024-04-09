cbuffer constants : register(b1) {
    float2 rn_screenSize;
    float2 oneOverAtlasSize;
}

/////////

struct sprite {
    float2 screenPos;
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

    float4 pos = float4(sp.screenPos, sp.screenPos + sp.size);
    float4 tex = float4(sp.texPos, sp.texPos + sp.texSize);

    uint2 i = { vertexId & 2, (vertexId << 1 & 2) ^ 3 };

    pixel p;

    p.pos = float4(float2(pos[i.x], pos[i.y]) * rn_screenSize - float2(1, -1), 0, 1);
    p.uv =        float2(tex[i.x], tex[i.y]) * oneOverAtlasSize;

    p.color = sp.color;

    return p;
}

float4 ps_main(pixel p) : SV_TARGET
{
    float4 color = tex.Sample(texSampler, p.uv);

    if (color.a == 0) discard;

    // color.rgb *= color.a;

    return color * p.color;
}