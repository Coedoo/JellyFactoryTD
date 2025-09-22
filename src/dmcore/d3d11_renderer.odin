#+build windows
package dmcore

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import d3d "vendor:directx/d3d_compiler"

// import sdl "vendor:sdl2"

import "core:fmt"
import "core:c/libc"
import "core:mem"

import sa "core:container/small_array"

import "core:image"

import "core:math/linalg/glsl"

BlitShaderSource := #load("shaders/hlsl/Blit.hlsl", string)
RectShaderSource := #load("shaders/hlsl/Rect.hlsl", string)
SpriteShaderSource := #load("shaders/hlsl/Sprite.hlsl", string)
SDFFontSource := #load("shaders/hlsl/SDFFont.hlsl", string)
GridShaderSource := #load("shaders/hlsl/Grid.hlsl", string)

//////////////////////
/// RENDER CONTEXT
//////////////////////

RenderContextBackend :: struct {
    device: ^d3d11.IDevice,
    deviceContext: ^d3d11.IDeviceContext,
    swapchain: ^dxgi.ISwapChain1,

    rasterizerState: ^d3d11.IRasterizerState,

    ppTextureSampler: ^d3d11.ISamplerState,

    screenRenderTarget: ^d3d11.IRenderTargetView,

    ppGlobalUniformBuffer: ^d3d11.IBuffer,

    blendState: ^d3d11.IBlendState,

    cameraConstBuff: ^d3d11.IBuffer,

    // Debug, @TODO: do something about it
    gpuVertBuffer: ^d3d11.IBuffer,
    inputLayout: ^d3d11.IInputLayout,
}

CreateRenderContextBackend :: proc(nativeWnd: dxgi.HWND) -> ^RenderContext {
    // @TODO: allocation
    ctx := new(RenderContext)

    featureLevels := [?]d3d11.FEATURE_LEVEL{._11_0}

    d3d11.CreateDevice(nil, .HARDWARE, nil, {.BGRA_SUPPORT}, &featureLevels[0], len(featureLevels),
                       d3d11.SDK_VERSION, &ctx.device, nil, &ctx.deviceContext)

    dxgiDevice: ^dxgi.IDevice
    ctx.device->QueryInterface(dxgi.IDevice_UUID, (^rawptr)(&dxgiDevice))

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

    dxgiFactory->CreateSwapChainForHwnd(ctx.device, nativeWnd, &swapchainDesc, nil, nil, &ctx.swapchain)

    rasterizerDesc := d3d11.RASTERIZER_DESC{
        FillMode = .SOLID,
        CullMode = .NONE,
        // ScissorEnable = true,
        DepthClipEnable = true,
        // MultisampleEnable = true,
        // AntialiasedLineEnable = true,
    }

    ctx.device->CreateRasterizerState(&rasterizerDesc, &ctx.rasterizerState)

    ////

    // ResizeFramebuffer(ctx, defaultWindowWidth, defaultWindowHeight)
    // screenFramebuffer: ^d3d11.ITexture2D
    // ctx.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&screenFramebuffer))

    // framebufferView: ^d3d11.IRenderTargetView
    // ctx.device->CreateRenderTargetView(screenFramebuffer, nil, &ctx.screenRenderTarget)

    // screenFramebuffer->Release()

    samplerDesc := d3d11.SAMPLER_DESC {
        Filter         = .MIN_MAG_MIP_POINT,
        AddressU       = .CLAMP,
        AddressV       = .CLAMP,
        AddressW       = .CLAMP,
        ComparisonFunc = .NEVER,
    }

    ctx.device->CreateSamplerState(&samplerDesc, &ctx.ppTextureSampler)

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

    ctx.device->CreateBlendState(&blendDesc, &ctx.blendState)

    ////

    constBuffDesc := d3d11.BUFFER_DESC {
        ByteWidth = size_of(PerFrameData),
        Usage = .DYNAMIC,
        BindFlags = { .CONSTANT_BUFFER },
        CPUAccessFlags = { .WRITE },
    }

    ctx.device->CreateBuffer(&constBuffDesc, nil, &ctx.cameraConstBuff)

    ////

    ppBuffDesc := d3d11.BUFFER_DESC {
        ByteWidth = size_of(PostProcessGlobalData),
        Usage = .DYNAMIC,
        BindFlags = { .CONSTANT_BUFFER },
        CPUAccessFlags = { .WRITE },
    }

    res := ctx.device->CreateBuffer(&ppBuffDesc, nil, &ctx.ppGlobalUniformBuffer)

    return ctx
}

StartFrame :: proc(ctx: ^RenderContext) {
    SetCamera(ctx.camera)

    viewport := d3d11.VIEWPORT {
        0, 0,
        f32(ctx.frameSize.x), f32(ctx.frameSize.y),
        0, 1,
    }

    // @TODO: make this settable
    ctx.deviceContext->RSSetViewports(1, &viewport)
    ctx.deviceContext->RSSetState(ctx.rasterizerState)

    // ctx.deviceContext->OMSetRenderTargets(1, &ctx.screenRenderTarget, nil)

    renderTarget := GetElement(ctx.framebuffers, ctx.ppFramebufferSrc)
    ctx.deviceContext->OMSetRenderTargets(1, &renderTarget.renderTargetView, nil)
    ctx.deviceContext->OMSetBlendState(ctx.blendState, nil, ~u32(0))
}

EndFrame :: proc(ctx: ^RenderContext) {
    DrawBatch(ctx, &ctx.defaultBatch)

    assert(sa.len(ctx.shadersStack) == 0)

    // Final Blit
    ctx.deviceContext->OMSetRenderTargets(1, &ctx.screenRenderTarget, nil)
    ctx.deviceContext->IASetPrimitiveTopology(.TRIANGLESTRIP)

    shader := GetElement(ctx.shaders, ctx.defaultShaders[.Blit])

    ctx.deviceContext->VSSetShader(shader.vertexShader, nil, 0)
    ctx.deviceContext->PSSetShader(shader.pixelShader, nil, 0)
    ppSrc := GetElement(ctx.framebuffers, ctx.ppFramebufferSrc)
    ctx.deviceContext->PSSetShaderResources(0, 1, &ppSrc.textureView)
    ctx.deviceContext->PSSetSamplers(0, 1, &ctx.ppTextureSampler)

    ctx.deviceContext->Draw(4, 0)

    ctx.swapchain->Present(1, nil)
}


////////////////////
// Primitive Buffer
///////////////


CreatePrimitiveBatch :: proc(ctx: ^RenderContext, maxCount: int, shaderSource: string) -> (ret: PrimitiveBatch) {
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
    ret.shader = CompileShaderSource(ctx, "Primitive Batch", shaderSource);

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

DrawPrimitiveBatch :: proc(ctx: ^RenderContext, batch: ^PrimitiveBatch) {
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

ClearColor :: proc(color: color) {
    color := color
    rt := GetElement(renderCtx.framebuffers, renderCtx.ppFramebufferSrc)
    renderCtx.deviceContext->ClearRenderTargetView(rt.renderTargetView, transmute(^[4]f32) &color)
}

SetCamera :: proc(camera: Camera) {
    view := GetViewMatrix(camera)
    proj := GetProjectionMatrixZTO(camera)

    mapped: d3d11.MAPPED_SUBRESOURCE
    renderCtx.deviceContext->Map(renderCtx.cameraConstBuff, 0, .WRITE_DISCARD, nil, &mapped);
    c := cast(^PerFrameData) mapped.pData
    c.VPMat = proj * view
    c.invVPMat = glsl.inverse(proj * view)
    c.screenSpace = 0

    renderCtx.deviceContext->Unmap(renderCtx.cameraConstBuff, 0)
    renderCtx.deviceContext->VSSetConstantBuffers(0, 1, &renderCtx.cameraConstBuff)
}

DrawMesh :: proc(mesh: ^Mesh, pos: v2, shader: ShaderHandle) {

}

DrawGrid :: proc() {
    DrawBatch(renderCtx, &renderCtx.defaultBatch)

    shaderHandle := renderCtx.defaultShaders[.Grid]
    shader := GetElement(renderCtx.shaders, shaderHandle)

    renderCtx.deviceContext->VSSetShader(shader.backend.vertexShader, nil, 0)
    renderCtx.deviceContext->PSSetShader(shader.backend.pixelShader, nil, 0)

    renderCtx.deviceContext->IASetPrimitiveTopology(.TRIANGLESTRIP)

    renderCtx.deviceContext->Draw(4, 0)
}

PushShader :: proc(shader: ShaderHandle) {
    sa.push(&renderCtx.shadersStack, shader)
}

PopShader :: proc() {
    sa.pop_back(&renderCtx.shadersStack)
}

BeginScreenSpace :: proc() {
    renderCtx.inScreenSpace = true

    DrawBatch(renderCtx, &renderCtx.defaultBatch)

    scale := [3]f32{2.0 / f32(renderCtx.frameSize.x), -2.0 / f32(renderCtx.frameSize.y), 0}
    mat := glsl.mat4Translate({-1, 1, 0}) * glsl.mat4Scale(scale)

    mapped: d3d11.MAPPED_SUBRESOURCE
    renderCtx.deviceContext->Map(renderCtx.cameraConstBuff, 0, .WRITE_DISCARD, nil, &mapped)
    c := cast(^PerFrameData) mapped.pData
    c.VPMat = mat
    c.invVPMat = glsl.inverse(mat)
    c.screenSpace = 1

    renderCtx.deviceContext->Unmap(renderCtx.cameraConstBuff, 0)
    renderCtx.deviceContext->VSSetConstantBuffers(0, 1, &renderCtx.cameraConstBuff)
}

EndScreenSpace :: proc() {
    DrawBatch(renderCtx, &renderCtx.defaultBatch)

    // TODO: cameras stack or something
    SetCamera(renderCtx.camera)
    renderCtx.inScreenSpace = false
}

UpdateBufferContent :: proc(buffer: GPUBufferHandle) {
    buff, ok := GetElementPtr(renderCtx.buffers, buffer)
    if ok {
        BackendUpdateBufferData(buff)
    }
}

BindBuffer :: proc(buffer: GPUBufferHandle, slot: int) {
    buff, ok := GetElementPtr(renderCtx.buffers, buffer)
    renderCtx.deviceContext -> PSSetConstantBuffers(cast(u32) slot, 1, &buff.d3dBuffer)
}

BindFramebufferAsTexture :: proc(framebuffer: FramebufferHandle, slot: int) {
    fb := GetElement(renderCtx.framebuffers, framebuffer)
    renderCtx.deviceContext->PSSetShaderResources(cast(u32) slot, 1, &fb.textureView)
}

BindRenderTarget :: proc(framebuffer: FramebufferHandle) {
    panic("unfinished")
}

BeginPP :: proc() {
    DrawBatch(renderCtx, &renderCtx.defaultBatch)

    // upload global uniform data
    ppMapped: d3d11.MAPPED_SUBRESOURCE
    res := renderCtx.deviceContext->Map(renderCtx.ppGlobalUniformBuffer, 0, .WRITE_DISCARD, nil, &ppMapped)

    data := cast(^PostProcessGlobalData) ppMapped.pData
    data.resolution = renderCtx.frameSize
    data.time = cast(f32) time.gameTime
    renderCtx.deviceContext->Unmap(renderCtx.ppGlobalUniformBuffer, 0)

    renderCtx.deviceContext->PSSetConstantBuffers(0, 1, &renderCtx.ppGlobalUniformBuffer)
}

DrawPP :: proc(pp: PostProcess) {
    shader := GetElement(renderCtx.shaders, pp.shader)
    if shader.vertexShader == nil || shader.pixelShader == nil {
        return
    }

    srcFB := GetElement(renderCtx.framebuffers, renderCtx.ppFramebufferSrc)
    destFB := GetElement(renderCtx.framebuffers, renderCtx.ppFramebufferDest)

    renderCtx.deviceContext->OMSetRenderTargets(1, &destFB.renderTargetView, nil)

    renderCtx.deviceContext->VSSetShader(shader.vertexShader, nil, 0)
    renderCtx.deviceContext->PSSetShader(shader.pixelShader, nil, 0)
    renderCtx.deviceContext->PSSetShaderResources(0, 1, &srcFB.textureView)
    renderCtx.deviceContext->PSSetSamplers(0, 1, &renderCtx.ppTextureSampler)

    renderCtx.deviceContext->IASetPrimitiveTopology(.TRIANGLESTRIP)
    renderCtx.deviceContext->Draw(4, 0)

    // Swap buffers for next pass, if there is one
    renderCtx.ppFramebufferSrc, renderCtx.ppFramebufferDest = renderCtx.ppFramebufferDest, renderCtx.ppFramebufferSrc
}

FinishPP :: proc() {
    srcFB := GetElement(renderCtx.framebuffers, renderCtx.ppFramebufferSrc)
    renderCtx.deviceContext->OMSetRenderTargets(1, &srcFB.renderTargetView, nil)
}






// Leaving it here in case I needed to return to that solution

// FlushCommands :: proc(ctx: ^RenderContext) {
//     renderTarget := GetElement(ctx.framebuffers, ctx.ppFramebufferSrc)
//     ctx.deviceContext->OMSetRenderTargets(1, &renderTarget.renderTargetView, nil)
//     ctx.deviceContext->OMSetBlendState(ctx.blendState, nil, ~u32(0))

//     shadersStack: sa.Small_Array(128, ShaderHandle)

//     for c in &ctx.commandBuffer.commands {
//         switch &cmd in c {
//         case ClearColorCommand:
//             rt := GetElement(ctx.framebuffers, ctx.ppFramebufferSrc)
//             ctx.deviceContext->ClearRenderTargetView(renderTarget.renderTargetView, transmute(^[4]f32) &cmd.clearColor)

//         case CameraCommand:
//             view := GetViewMatrix(cmd.camera)
//             proj := GetProjectionMatrixZTO(cmd.camera)

//             mapped: d3d11.MAPPED_SUBRESOURCE
//             ctx.deviceContext->Map(ctx.cameraConstBuff, 0, .WRITE_DISCARD, nil, &mapped);
//             c := cast(^PerFrameData) mapped.pData
//             c.VPMat = proj * view
//             c.invVPMat = glsl.inverse(proj * view)
//             c.screenSpace = 0

//             ctx.deviceContext->Unmap(ctx.cameraConstBuff, 0)
//             ctx.deviceContext->VSSetConstantBuffers(0, 1, &ctx.cameraConstBuff)

//         case DrawRectCommand:
//             if ctx.defaultBatch.count >= ctx.defaultBatch.maxCount {
//                 DrawBatch(ctx, &ctx.defaultBatch)
//             }

//             shadersLen := sa.len(shadersStack)
//             shader :=  shadersLen > 0 ? sa.get(shadersStack, shadersLen - 1) : cmd.shader

//             if ctx.defaultBatch.shader.gen != 0 && 
//                ctx.defaultBatch.shader != shader {
//                 DrawBatch(ctx, &ctx.defaultBatch)
//             }

//             if ctx.defaultBatch.texture.gen != 0 && 
//                ctx.defaultBatch.texture != cmd.texture {
//                 DrawBatch(ctx, &ctx.defaultBatch)
//             }

//             ctx.defaultBatch.shader = shader
//             ctx.defaultBatch.texture = cmd.texture

//             entry := RectBatchEntry {
//                 position = cmd.position,
//                 size = cmd.size,
//                 rotation = cmd.rotation,

//                 texPos  = {cmd.texSource.x, cmd.texSource.y},
//                 texSize = {cmd.texSource.width, cmd.texSource.height},
//                 pivot = cmd.pivot,
//                 color = cmd.tint,
//             }

//             AddBatchEntry(ctx, &ctx.defaultBatch, entry)

//         case DrawGridCommand:
//             DrawBatch(ctx, &ctx.defaultBatch)

//             shaderHandle := ctx.defaultShaders[.Grid]
//             shader := GetElement(ctx.shaders, shaderHandle)

//             ctx.deviceContext->VSSetShader(shader.backend.vertexShader, nil, 0)
//             ctx.deviceContext->PSSetShader(shader.backend.pixelShader, nil, 0)

//             ctx.deviceContext->IASetPrimitiveTopology(.TRIANGLESTRIP)

//             ctx.deviceContext->Draw(4, 0)

//         case DrawMeshCommand:

//         case PushShaderCommand: sa.push(&shadersStack, cmd.shader)
//         case PopShaderCommand:  sa.pop_back(&shadersStack)

//         case BeginScreenSpaceCommand:
//             DrawBatch(ctx, &ctx.defaultBatch)

//             scale := [3]f32{ 2.0 / f32(ctx.frameSize.x), -2.0 / f32(ctx.frameSize.y), 0}
//             mat := glsl.mat4Translate({-1, 1, 0}) * glsl.mat4Scale(scale)

//             mapped: d3d11.MAPPED_SUBRESOURCE
//             ctx.deviceContext->Map(ctx.cameraConstBuff, 0, .WRITE_DISCARD, nil, &mapped);
//             c := cast(^PerFrameData) mapped.pData
//             c.VPMat = mat
//             c.invVPMat = glsl.inverse(mat)
//             c.screenSpace = 1

//             ctx.deviceContext->Unmap(ctx.cameraConstBuff, 0)
//             ctx.deviceContext->VSSetConstantBuffers(0, 1, &ctx.cameraConstBuff)

//         case EndScreenSpaceCommand:
//             DrawBatch(ctx, &ctx.defaultBatch)

//         case BindFBAsTextureCommand:
//             fb := GetElement(ctx.framebuffers, cmd.framebuffer)
//             ctx.deviceContext->PSSetShaderResources(cast(u32) cmd.slot, 1, &fb.textureView)

//         case BindRenderTargetCommand:
//             panic("unfinished")

//         case UpdateBufferContentCommand:
//             buff, ok := GetElementPtr(ctx.buffers, cmd.buffer)
//             if ok {
//                 BackendUpdateBufferData(buff)
//             }

//         case BindBufferCommand:
//             buff, ok := GetElementPtr(ctx.buffers, cmd.buffer)
//             ctx.deviceContext -> PSSetConstantBuffers(cast(u32) cmd.slot, 1, &buff.d3dBuffer)

//         case BeginPPCommand:
//             DrawBatch(ctx, &ctx.defaultBatch)

//             // upload global uniform data
//             ppMapped: d3d11.MAPPED_SUBRESOURCE
//             res := ctx.deviceContext->Map(ctx.ppGlobalUniformBuffer, 0, .WRITE_DISCARD, nil, &ppMapped)

//             data := cast(^PostProcessGlobalData) ppMapped.pData
//             data.resolution = ctx.frameSize
//             data.time = cast(f32) time.gameTime
//             ctx.deviceContext->Unmap(ctx.ppGlobalUniformBuffer, 0)

//             ctx.deviceContext->PSSetConstantBuffers(0, 1, &ctx.ppGlobalUniformBuffer)

//         case DrawPPCommand:
//             shader := GetElement(ctx.shaders, cmd.shader)
//             if shader.vertexShader == nil || shader.pixelShader == nil {
//                 continue
//             }

//             srcFB := GetElement(ctx.framebuffers, ctx.ppFramebufferSrc)
//             destFB := GetElement(ctx.framebuffers, ctx.ppFramebufferDest)

//             ctx.deviceContext->OMSetRenderTargets(1, &destFB.renderTargetView, nil)

//             ctx.deviceContext->VSSetShader(shader.vertexShader, nil, 0)
//             ctx.deviceContext->PSSetShader(shader.pixelShader, nil, 0)
//             ctx.deviceContext->PSSetShaderResources(0, 1, &srcFB.textureView)
//             ctx.deviceContext->PSSetSamplers(0, 1, &ctx.ppTextureSampler)

//             ctx.deviceContext->IASetPrimitiveTopology(.TRIANGLESTRIP)
//             ctx.deviceContext->Draw(4, 0)

//             // Swap buffers for next pass, if there is one
//             ctx.ppFramebufferSrc, ctx.ppFramebufferDest = ctx.ppFramebufferDest, ctx.ppFramebufferSrc

//         case FinishPPCommand:
//             srcFB := GetElement(ctx.framebuffers, ctx.ppFramebufferSrc)
//             ctx.deviceContext->OMSetRenderTargets(1, &srcFB.renderTargetView, nil)
//         }
//     }

//     DrawBatch(ctx, &ctx.defaultBatch)
//     clear(&ctx.commandBuffer.commands)

//     // // Final Blit
//     ctx.deviceContext->OMSetRenderTargets(1, &ctx.screenRenderTarget, nil)

//     shader := GetElement(ctx.shaders, ctx.defaultShaders[.Blit])

//     ctx.deviceContext->VSSetShader(shader.vertexShader, nil, 0)
//     ctx.deviceContext->PSSetShader(shader.pixelShader, nil, 0);
//     ppSrc := GetElement(ctx.framebuffers, ctx.ppFramebufferSrc)
//     ctx.deviceContext->PSSetShaderResources(0, 1, &ppSrc.textureView)
//     ctx.deviceContext->PSSetSamplers(0, 1, &ctx.ppTextureSampler)

//     ctx.deviceContext->Draw(4, 0)
// }