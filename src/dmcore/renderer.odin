package dmcore

import "core:mem"
import "core:encoding/base64"

TexHandle :: distinct Handle
ShaderHandle :: distinct Handle
BatchHandle :: distinct Handle

defaultWindowWidth  :: 1200
defaultWindowHeight :: 900

UNIFORM_MEM :: 1 * mem.Megabyte

RenderContext :: struct {
    whiteTexture: TexHandle,

    frameSize: iv2,

    defaultBatch: RectBatch,
    debugBatch:   PrimitiveBatch,
    debugBatchScreen: PrimitiveBatch,

    commandBuffer: CommandBuffer,

    textures:     ResourcePool(Texture, TexHandle),
    shaders:      ResourcePool(Shader, ShaderHandle),
    buffers:      ResourcePool(GPUBuffer, GPUBufferHandle),
    fonts:        ResourcePool(Font, FontHandle),
    framebuffers: ResourcePool(Framebuffer, FramebufferHandle),

    defaultShaders: [DefaultShaderType]ShaderHandle,

    uniformArena: mem.Arena,
    uniformAllocator: mem.Allocator,

    ppFramebufferSrc:  FramebufferHandle,
    ppFramebufferDest: FramebufferHandle,

    camera: Camera,

    inScreenSpace: bool,

    using backend: RenderContextBackend,
}

Mesh :: struct {
    verts: []v3,
    indices: []i32,
}

PerFrameData :: struct {
    VPMat: mat4,
    invVPMat: mat4,
    screenSpace: i32,
}

InitRenderContext :: proc(ctx: ^RenderContext) -> ^RenderContext {
    //@TODO: How many textures do I need? Maybe make it dynamic?
    InitResourcePool(&ctx.textures, 128)
    InitResourcePool(&ctx.shaders, 64)
    InitResourcePool(&ctx.buffers, 64)
    InitResourcePool(&ctx.fonts, 4)
    InitResourcePool(&ctx.framebuffers, 16)

    // Batches
    InitRectBatch(ctx, &ctx.defaultBatch, 1024)
    ctx.debugBatch = CreatePrimitiveBatch(ctx, 4086, PrimitiveVertexShaderSource)
    ctx.debugBatchScreen = CreatePrimitiveBatch(ctx, 4086, PrimitiveVertexScreenShaderSource)

    // Shaders
    ctx.defaultShaders[.Blit] = CompileShaderSource(ctx, "Blit", BlitShaderSource)
    ctx.defaultShaders[.Sprite] = CompileShaderSource(ctx, "Sprite", SpriteShaderSource)
    ctx.defaultShaders[.Rect] = CompileShaderSource(ctx, "Rect", RectShaderSource)
    ctx.defaultShaders[.SDFFont] = CompileShaderSource(ctx, "SDFFont", SDFFontSource)
    ctx.defaultShaders[.Grid] = CompileShaderSource(ctx, "Grid", GridShaderSource)

    // Camera and window
    ctx.frameSize = { defaultWindowWidth, defaultWindowHeight }
    ctx.camera = CreateCamera(5, f32(defaultWindowWidth)/f32(defaultWindowHeight))

    // memory
    uniformMem := make([]byte, UNIFORM_MEM)
    mem.arena_init(&ctx.uniformArena, uniformMem)
    ctx.uniformAllocator = mem.arena_allocator(&ctx.uniformArena)

    // framebuffers
    ctx.ppFramebufferSrc  = CreateFramebuffer(ctx)
    ctx.ppFramebufferDest = CreateFramebuffer(ctx)

    // Default assets
    texData := []u8{255, 255, 255, 255}
    ctx.whiteTexture = CreateTexture(ctx, texData, 1, 1, 4, .Point)

    errorTex := &ctx.textures.elements[0]
    texData = []u8{255, 255, 0, 255}
    _InitTexture(ctx, errorTex, texData, 1, 1, 4, .Point)

    atlasData := base64.decode(DEFAULT_FONT_ATLAS, allocator = context.temp_allocator)
    fontType:TextureFilter = DefaultFont.type == .SDF ? .Bilinear : .Point
    DefaultFont.atlas = CreateTexture(ctx, atlasData, DEFAULT_FONT_ATLAS_SIZE, DEFAULT_FONT_ATLAS_SIZE, 4, fontType)

    ctx.fonts.elements[0] = DefaultFont

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
