//+build windows
package dmcore

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import d3d "vendor:directx/d3d_compiler"

import sdl "vendor:sdl2"

import "core:fmt"
import "core:c/libc"
import "core:mem"

import sa "core:container/small_array"

import "core:image"

import "core:math/linalg/glsl"

ScreenSpaceRectShaderSource := #load("shaders/hlsl/ScreenSpaceRect.hlsl", string)
SpriteShaderSource := #load("shaders/hlsl/Sprite.hlsl", string)
SDFFontSource := #load("shaders/hlsl/SDFFont.hlsl", string)
GridShaderSource := #load("shaders/hlsl/Grid.hlsl", string)

//////////////////////
/// RENDER CONTEXT
//////////////////////

RenderContext_d3d :: struct {
    using base: RenderContext,

    device: ^d3d11.IDevice,
    deviceContext: ^d3d11.IDeviceContext,
    swapchain: ^dxgi.ISwapChain1,

    rasterizerState: ^d3d11.IRasterizerState,

    framebuffer: ^d3d11.ITexture2D,
    framebufferView: ^d3d11.IRenderTargetView,

    blendState: ^d3d11.IBlendState,

    cameraConstBuff: ^d3d11.IBuffer,

    // Debug, @TODO: do something about it
    gpuVertBuffer: ^d3d11.IBuffer,
    inputLayout: ^d3d11.IInputLayout,
}

CreateRenderContext :: proc(window: ^sdl.Window) -> ^RenderContext {

    window_system_info: sdl.SysWMinfo

    // @TODO:
    // Probably don't want using sdl here
    sdl.GetVersion(&window_system_info.version)
    sdl.GetWindowWMInfo(window, &window_system_info)
    assert(window_system_info.subsystem == .WINDOWS)

    nativeWnd := dxgi.HWND(window_system_info.info.win.window)

    featureLevels := [?]d3d11.FEATURE_LEVEL{._11_0}

    device: ^d3d11.IDevice
    deviceContext: ^d3d11.IDeviceContext
    swapchain: ^dxgi.ISwapChain1

    d3d11.CreateDevice(nil, .HARDWARE, nil, {.BGRA_SUPPORT}, &featureLevels[0], len(featureLevels),
                       d3d11.SDK_VERSION, &device, nil, &deviceContext)
    
    // device: ^d3d11.IDevice
    // baseDevice->QueryInterface(d3d11.IDevice_UUID, (^rawptr)(&device))

    // deviceContext: ^d3d11.IDeviceContext
    // baseDeviceContext->QueryInterface(d3d11.IDeviceContext_UUID, (^rawptr)(&deviceContext))

    dxgiDevice: ^dxgi.IDevice
    device->QueryInterface(dxgi.IDevice_UUID, (^rawptr)(&dxgiDevice))

    dxgiAdapter: ^dxgi.IAdapter
    dxgiDevice->GetAdapter(&dxgiAdapter)

    dxgiFactory: ^dxgi.IFactory2
    dxgiAdapter->GetParent(dxgi.IFactory2_UUID, (^rawptr)(&dxgiFactory))

    defer dxgiFactory->Release();
    defer dxgiAdapter->Release();
    defer dxgiDevice->Release();

    /////

    swapchainDesc := dxgi.SWAP_CHAIN_DESC1{
        Width  = 0,
        Height = 0,
        Format = .B8G8R8A8_UNORM_SRGB,
        Stereo = false,
        SampleDesc = {
            Count   = 1,
            Quality = 0,
        },
        BufferUsage = {.RENDER_TARGET_OUTPUT},
        BufferCount = 2,
        Scaling     = .STRETCH,
        SwapEffect  = .DISCARD,
        AlphaMode   = .UNSPECIFIED,
        Flags       = nil,
    }

    dxgiFactory->CreateSwapChainForHwnd(device, nativeWnd, &swapchainDesc, nil, nil, &swapchain)

    rasterizerDesc := d3d11.RASTERIZER_DESC{
        FillMode = .SOLID,
        CullMode = .NONE,
        // ScissorEnable = true,
        DepthClipEnable = true,
        // MultisampleEnable = true,
        // AntialiasedLineEnable = true,
    }

    rasterizerState: ^d3d11.IRasterizerState
    device->CreateRasterizerState(&rasterizerDesc, &rasterizerState)

    ////
    framebuffer: ^d3d11.ITexture2D
    swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&framebuffer))

    framebufferView: ^d3d11.IRenderTargetView
    device->CreateRenderTargetView(framebuffer, nil, &framebufferView)

    framebuffer->Release()

    /////
    blendDesc: d3d11.BLEND_DESC
    blendDesc.RenderTarget[0] = {
        BlendEnable = true,
        SrcBlend = .SRC_ALPHA,
        DestBlend = .INV_SRC_ALPHA,
        BlendOp = .ADD,
        SrcBlendAlpha = .SRC_ALPHA,
        DestBlendAlpha = .INV_SRC_ALPHA,
        BlendOpAlpha = .ADD,
        RenderTargetWriteMask = 0b1111,
    }

    blendState: ^d3d11.IBlendState
    device->CreateBlendState(&blendDesc, &blendState)

    ////

    // @TODO: allocation
    ctx := new(RenderContext_d3d)

    ctx.device = device
    ctx.deviceContext = deviceContext
    ctx.swapchain = swapchain

    ctx.rasterizerState = rasterizerState

    ctx.framebuffer = framebuffer
    ctx.framebufferView = framebufferView

    ctx.blendState = blendState

    //@TODO: How many textures do I need? Maybe make it dynamic?
    InitResourcePool(&ctx.textures, 128)
    InitResourcePool(&ctx.shaders, 64)

    texData := []u8{255, 255, 255, 255}
    ctx.whiteTexture = CreateTexture(ctx, texData, 1, 1, 4, .Point)

    errorTex := &ctx.textures.elements[0]
    texData = []u8{255, 255, 0, 255}
    _InitTexture(ctx, errorTex, texData, 1, 1, 4, .Point)

    // ctx.defaultBatch = CreateRectBatch(&ctx, 8);

    // ctx.DrawBatch = DrawBatch

    InitRectBatch(ctx, &ctx.defaultBatch, 1024)
    ctx.debugBatch = CreatePrimitiveBatch(ctx, 4086, PrimitiveVertexShaderSource)
    ctx.debugBatchScreen = CreatePrimitiveBatch(ctx, 4086, PrimitiveVertexScreenShaderSource)

    constBuffDesc := d3d11.BUFFER_DESC {
        ByteWidth = size_of(mat4),
        Usage = .DYNAMIC,
        BindFlags = { .CONSTANT_BUFFER },
        CPUAccessFlags = { .WRITE },
    }

    ctx.device->CreateBuffer(&constBuffDesc, nil, &ctx.cameraConstBuff)

    ctx.defaultShaders[.ScreenSpaceRect] = CompileShaderSource(ctx, ScreenSpaceRectShaderSource)
    ctx.defaultShaders[.Sprite] = CompileShaderSource(ctx, SpriteShaderSource)
    ctx.defaultShaders[.SDFFont] = CompileShaderSource(ctx, SDFFontSource)
    ctx.defaultShaders[.Grid] = CompileShaderSource(ctx, GridShaderSource)

    ctx.camera = CreateCamera(5, 4./3.)

    return ctx
}

// BeginRenderFrame :: proc(ctx: ^RenderContext) {
//     ctx := cast(^RenderContext_d3d) ctx

//     viewport := d3d11.VIEWPORT {
//         0, 0,
//         windowWidth, windowHeight,
//         0, 1,
//     }

//     // @TODO: move clearing render target to another function?
//     ctx.deviceContext->ClearRenderTargetView(ctx.framebufferView, &[4]f32{0.25, 0.5, 1.0, 1.0})

//     ctx.deviceContext->RSSetViewports(1, &viewport)
//     ctx.deviceContext->RSSetState(ctx.rasterizerState)

//     ctx.deviceContext->OMSetRenderTargets(1, &ctx.framebufferView, nil)
//     ctx.deviceContext->OMSetBlendState(ctx.blendState, nil, ~u32(0))
// }

EndFrame :: proc(ctx: ^RenderContext_d3d) {
    ctx.swapchain->Present(1, nil)
}

FlushCommands :: proc(using ctx: ^RenderContext_d3d) {

    viewport := d3d11.VIEWPORT {
        0, 0,
        f32(frameSize.x), f32(frameSize.y),
        0, 1,
    }

    // @TODO: make this settable
    ctx.deviceContext->RSSetViewports(1, &viewport)
    ctx.deviceContext->RSSetState(ctx.rasterizerState)

    ctx.deviceContext->OMSetRenderTargets(1, &ctx.framebufferView, nil)
    ctx.deviceContext->OMSetBlendState(ctx.blendState, nil, ~u32(0))

    // Default Camera
    view := GetViewMatrix(ctx.camera)
    proj := GetProjectionMatrixZTO(ctx.camera)

    CameraConst :: struct {
        vpMat: mat4,
        invVPMap: mat4,
    }

    mapped: d3d11.MAPPED_SUBRESOURCE
    res := ctx.deviceContext->Map(ctx.cameraConstBuff, 0, .WRITE_DISCARD, nil, &mapped);
    c := cast(^CameraConst) mapped.pData
    c.vpMat = proj * view
    c.invVPMap = glsl.inverse(proj * view)

    ctx.deviceContext->Unmap(ctx.cameraConstBuff, 0)
    ctx.deviceContext->VSSetConstantBuffers(0, 1, &ctx.cameraConstBuff)

    shadersStack: sa.Small_Array(128, ShaderHandle)

    for c in &commandBuffer.commands {
        switch &cmd in c {
        case ClearColorCommand:
            deviceContext->ClearRenderTargetView(framebufferView, transmute(^[4]f32) &cmd.clearColor)

        case CameraCommand:
            view := GetViewMatrix(cmd.camera)
            proj := GetProjectionMatrixZTO(cmd.camera)

            mapped: d3d11.MAPPED_SUBRESOURCE
            res := ctx.deviceContext->Map(ctx.cameraConstBuff, 0, .WRITE_DISCARD, nil, &mapped);
            c := cast(^CameraConst) mapped.pData
            c.vpMat = proj * view
            c.invVPMap = glsl.inverse(proj * view)

            ctx.deviceContext->Unmap(ctx.cameraConstBuff, 0)
            ctx.deviceContext->VSSetConstantBuffers(0, 1, &ctx.cameraConstBuff)

        case DrawRectCommand:
            if ctx.defaultBatch.count >= ctx.defaultBatch.maxCount {
                DrawBatch(ctx, &ctx.defaultBatch)
            }

            shadersLen := sa.len(shadersStack)
            shader :=  shadersLen > 0 ? sa.get(shadersStack, shadersLen - 1) : cmd.shader

            if ctx.defaultBatch.shader.gen != 0 && 
               ctx.defaultBatch.shader != shader {
                DrawBatch(ctx, &ctx.defaultBatch)
            }

            if ctx.defaultBatch.texture.gen != 0 && 
               ctx.defaultBatch.texture != cmd.texture {
                DrawBatch(ctx, &ctx.defaultBatch)
            }

            ctx.defaultBatch.shader = shader
            ctx.defaultBatch.texture = cmd.texture

            entry := RectBatchEntry {
                position = cmd.position,
                size = cmd.size,
                rotation = cmd.rotation,

                texPos  = {cmd.texSource.x, cmd.texSource.y},
                texSize = {cmd.texSource.width, cmd.texSource.height},
                pivot = cmd.pivot,
                color = cmd.tint,
            }

            AddBatchEntry(ctx, &ctx.defaultBatch, entry)

        case DrawGridCommand:
            shaderHandle := ctx.defaultShaders[.Grid]
            shader := GetElement(ctx.shaders, shaderHandle)

            ctx.deviceContext->VSSetShader(shader.backend.vertexShader, nil, 0)
            ctx.deviceContext->PSSetShader(shader.backend.pixelShader, nil, 0)

            ctx.deviceContext->Draw(4, 0)

        case DrawMeshCommand:

        case PushShaderCommand: sa.push(&shadersStack, cmd.shader)
        case PopShaderCommand:  sa.pop_back(&shadersStack)


        }
    }

    DrawBatch(ctx, &ctx.defaultBatch)

    clear(&commandBuffer.commands)
}

ResizeFrambuffer :: proc(renderCtx: ^RenderContext, width, height: int) {
    ctx := cast(^RenderContext_d3d) renderCtx

    ctx.deviceContext->OMSetRenderTargets(0, nil, nil)
    ctx.framebufferView->Release()

    ctx.swapchain->ResizeBuffers(0, 0, 0, .UNKNOWN, nil)

    framebuffer: ^d3d11.ITexture2D
    ctx.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&framebuffer))

    ctx.device->CreateRenderTargetView(framebuffer, nil, &ctx.framebufferView)

    framebuffer->Release()
}


////////////////////
// Primitive Buffer
///////////////

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

CreatePrimitiveBatch :: proc(ctx: ^RenderContext_d3d, maxCount: int, shaderSource: string) -> (ret: PrimitiveBatch) {

    // ctx.debugBatch.buffer = make([]PrimitiveVertex, maxCount)
    ret.buffer = make([dynamic]PrimitiveVertex, 0, maxCount)
    ret.gpuBufferSize = maxCount;

    // vert buffer
    desc := d3d11.BUFFER_DESC {
        ByteWidth = u32(maxCount) * size_of(PrimitiveVertex),
        Usage     = .DYNAMIC,
        BindFlags = { .VERTEX_BUFFER },
        CPUAccessFlags = { .WRITE },
    }

    res := ctx.device->CreateBuffer(&desc, nil, &ctx.gpuVertBuffer)
    ret.shader = CompileShaderSource(ctx, shaderSource);

    // @HACK: I need to somehow have shader byte code in order to create input layout
    // But my current implementation doesn't store shader bytecode so I need to compile it 
    // again to create the layout.
    // Maybe with precompiled shaders I could get away with
    vsBlob: ^d3d11.IBlob
    defer vsBlob->Release()

    error: ^d3d11.IBlob
    hr := d3d.Compile(raw_data(shaderSource), len(shaderSource), 
                      "shaders.hlsl", nil, nil, 
                      "vs_main", "vs_5_0", 0, 0, &vsBlob, &error)

    if hr < 0 {
        fmt.println(transmute(cstring) error->GetBufferPointer())
        error->Release()

        return
    }


    inputDescs: []d3d11.INPUT_ELEMENT_DESC = {
        {"POSITION", 0, .R32G32B32_FLOAT,    0,                            0, .VERTEX_DATA, 0 },
        {"COLOR",    0, .R32G32B32A32_FLOAT, 0, d3d11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
    }

    res = ctx.device->CreateInputLayout(&inputDescs[0], cast(u32) len(inputDescs), 
                          vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(),
                          &ctx.inputLayout)

    return
}

DrawPrimitiveBatch :: proc(batch: ^PrimitiveBatch, ctx: ^RenderContext_d3d) {
    count := len(batch.buffer)

    if count == 0 {
        return
    }

    mapped: d3d11.MAPPED_SUBRESOURCE

    shader := GetElement(ctx.shaders, batch.shader)

    stride: u32 = size_of(PrimitiveVertex)
    offset: u32 = 0

    ctx.deviceContext->IASetPrimitiveTopology(.LINELIST)
    ctx.deviceContext->IASetInputLayout(ctx.inputLayout)
    ctx.deviceContext->IASetVertexBuffers(0, 1, &ctx.gpuVertBuffer, &stride, &offset)

    ctx.deviceContext->VSSetShader(shader.backend.vertexShader, nil, 0)

    ctx.deviceContext->PSSetShader(shader.backend.pixelShader, nil, 0)

    // round up
    iterCount := (count + batch.gpuBufferSize - 1) / batch.gpuBufferSize

    for i in 0..<iterCount {
        drawCount := min(count, batch.gpuBufferSize)

        result := ctx.deviceContext->Map(ctx.gpuVertBuffer, 0, .WRITE_DISCARD, nil, &mapped)
        mem.copy(mapped.pData, &batch.buffer[i * batch.gpuBufferSize], drawCount * size_of(PrimitiveVertex))
        ctx.deviceContext->Unmap(ctx.gpuVertBuffer, 0)

        ctx.deviceContext->Draw(u32(drawCount), 0)

        count = count - batch.gpuBufferSize
    }

    clear(&batch.buffer)
}