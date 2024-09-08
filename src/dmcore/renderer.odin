package dmcore

import "core:mem"

TexHandle :: distinct Handle
ShaderHandle :: distinct Handle
BatchHandle :: distinct Handle

defaultWindowWidth  :: 800
defaultWindowHeight :: 600

UNIFORM_MEM :: 1 * mem.Megabyte

RenderContext :: struct {
    whiteTexture: TexHandle,

    frameSize: iv2,

    defaultBatch: RectBatch,
    debugBatch:   PrimitiveBatch,
    debugBatchScreen: PrimitiveBatch,

    commandBuffer: CommandBuffer,

    textures: ResourcePool(Texture, TexHandle),
    shaders: ResourcePool(Shader, ShaderHandle),

    defaultShaders: [DefaultShaderType]ShaderHandle,

    uniformArena: mem.Arena,
    uniformAllocator: mem.Allocator,

    camera: Camera,

    using backend: RenderContextBackend,
}

Mesh :: struct {
    verts: []v3,
    indices: []i32,
}

PerFrameData :: struct {
    VPMat: mat4,
    invVPMat: mat4,
}

InitRenderContext :: proc(ctx: ^RenderContext) -> ^RenderContext {
    //@TODO: How many textures do I need? Maybe make it dynamic?
    InitResourcePool(&ctx.textures, 128)
    InitResourcePool(&ctx.shaders, 64)

    texData := []u8{255, 255, 255, 255}
    ctx.whiteTexture = CreateTexture(ctx, texData, 1, 1, 4, .Point)

    errorTex := &ctx.textures.elements[0]
    texData = []u8{255, 255, 0, 255}
    _InitTexture(ctx, errorTex, texData, 1, 1, 4, .Point)

    InitRectBatch(ctx, &ctx.defaultBatch, 1024)
    ctx.debugBatch = CreatePrimitiveBatch(ctx, 4086, PrimitiveVertexShaderSource)
    ctx.debugBatchScreen = CreatePrimitiveBatch(ctx, 4086, PrimitiveVertexScreenShaderSource)

    ctx.defaultShaders[.ScreenSpaceRect] = CompileShaderSource(ctx, ScreenSpaceRectShaderSource)
    ctx.defaultShaders[.Sprite] = CompileShaderSource(ctx, SpriteShaderSource)
    ctx.defaultShaders[.SDFFont] = CompileShaderSource(ctx, SDFFontSource)
    ctx.defaultShaders[.Grid] = CompileShaderSource(ctx, GridShaderSource)

    ctx.frameSize = { defaultWindowWidth, defaultWindowHeight }
    ctx.camera = CreateCamera(5, f32(defaultWindowWidth)/f32(defaultWindowHeight))

    uniformMem := make([]byte, UNIFORM_MEM)
    mem.arena_init(&ctx.uniformArena, uniformMem)
    ctx.uniformAllocator = mem.arena_allocator(&ctx.uniformArena)


    return ctx
}

// @HACK:
when ODIN_OS == .Windows {
    PrimitiveVertexShaderSource := `
cbuffer constants: register(b0) {
    float4x4 VPMat;
}

struct vs_in {
    float3 position: POSITION;
    float4 color: COLOR;
};

struct vs_out {
    float4 position: SV_POSITION;
    float4 color: COLOR;
};

vs_out vs_main(vs_in input) {
    vs_out output;

    output.position = mul(VPMat, float4(input.position, 1));
    output.color = input.color;

    return output;
}

float4 ps_main(vs_out input) : SV_TARGET {
    return input.color;
}
`

    PrimitiveVertexScreenShaderSource := `
cbuffer constants : register(b1) {
    float2 rn_screenSize;
    float2 oneOverAtlasSize;
}

struct vs_in {
    float3 inPos: POSITION;
    float4 color: COLOR;
};

struct vs_out {
    float4 position: SV_POSITION;
    float4 color: COLOR;
};

vs_out vs_main(vs_in input) {
    vs_out output;

    float2 v = input.inPos.xy * rn_screenSize;
    output.position = float4(v - float2(1, -1), 0, 1);
    output.color = input.color;

    return output;
}

float4 ps_main(vs_out input) : SV_TARGET {
    return input.color;
}
`
} else when ODIN_OS == .JS {
    PrimitiveVertexShaderSource := ``
    PrimitiveVertexScreenShaderSource := ``
}
