cbuffer cameraConst : register(b0) {
    float4x4 VPMat;
    float4x4 invVPMat;
    int screenSpace;
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

    uint2 i = { vertexId & 2, (vertexId << 1 & 2) ^ 3 };
    // ^ this creates the series of numbers:
    // 0 : (0, 3)
    // 1 : (0, 1)
    // 2 : (2, 3)
    // 3 : (2, 1)

    float2 anchor = sp.pivot * sp.size;
    float4 pos = float4(
        0,
        sp.size.y,
        sp.size.x,
        0
    );

    float2 vertexPos = float2(pos[i.x], pos[i.y]) - anchor;

    float r = screenSpace == 1 ? -sp.rotation : sp.rotation;
    float2x2 rot = float2x2(cos(r), -sin(r),
                            sin(r),  cos(r));

    vertexPos = mul(rot, vertexPos);
    vertexPos += sp.pos;

    pixel p;
    p.pos = mul(VPMat, float4(vertexPos, 0, 1));
    p.pos.xyz /= p.pos.w;

    // 0 - for world space (Y up)
    // 1 - for screen space (Y down)
    const float4 texUVS[2] = {
        float4(sp.texPos, sp.texPos + sp.texSize),
        float4(sp.texPos.x, sp.texPos.y + sp.texSize.y, sp.texPos.x + sp.texSize.x, sp.texPos.y),
    };

    float4 tex = texUVS[screenSpace];
    p.uv = float2(tex[i.x], tex[i.y]);

    p.color = sp.color;

    return p;
}

float4 ps_main(pixel p) : SV_TARGET
{
    const float edge = 128.0 / 255.0;
    const float aa = 16.0 / 255.0;

    float dist = tex.Sample(texSampler, p.uv * oneOverAtlasSize).a;
    float alpha = smoothstep(edge - aa, edge + aa, dist);

    // return float4(p.uv, 1, 1);
    return float4(p.color.rgb, alpha);
}