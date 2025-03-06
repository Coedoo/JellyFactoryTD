#+build windows
package dmcore

import "core:mem"
import "core:fmt"

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import d3d "vendor:directx/d3d_compiler"

// SHADER

_Shader :: struct {
    vertexShader: ^d3d11.IVertexShader,
    pixelShader: ^d3d11.IPixelShader,
}

CompileShaderSource :: proc(renderCtx: ^RenderContext, name, source: string) -> ShaderHandle {
    shader := CreateElement(&renderCtx.shaders)
    shader.name = name

    if InitShaderSource(renderCtx, shader, source) {
        return shader.handle
    }

    return shader.handle
}

InitShaderSource :: proc(renderCtx: ^RenderContext, shader: ^Shader, source: string) -> (result: bool) {
    error: ^d3d11.IBlob
    vsBlob: ^d3d11.IBlob

    hr := d3d.Compile(raw_data(source), len(source), "shaders.hlsl", nil, nil, 
                      "vs_main", "vs_5_0", 0, 0, &vsBlob, &error)

    defer if result == false {
        if error               != nil do error->Release()
        if vsBlob              != nil do vsBlob->Release()
        if shader.vertexShader != nil do shader.vertexShader->Release()
        if shader.pixelShader  != nil do shader.pixelShader->Release()

        shader.pixelShader = nil
        shader.vertexShader = nil
    }

    if hr < 0 {
        fmt.println(transmute(cstring) error->GetBufferPointer())
        error->Release()

        result = false
        return
    }

    hr = renderCtx.device->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), 
                                         nil, &shader.backend.vertexShader)

    if hr != 0 {
        fmt.printf("%x\n", transmute(u32) hr)
        hr = renderCtx.device->GetDeviceRemovedReason()

        result = false
        return
    }

    psBlob: ^d3d11.IBlob
    hr = d3d.Compile(raw_data(source), len(source), "shaders.hlsl", nil, nil,
                     "ps_main", "ps_5_0", 0, 0, &psBlob, &error)

    if hr < 0 {
        fmt.println(transmute(cstring) error->GetBufferPointer())
        error->Release()

        result = false
        return
    }

    hr = renderCtx.device->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), 
                                        nil, &shader.backend.pixelShader)

    if hr != 0 {
        fmt.printf("%x\n", transmute(u32) hr)

        result = false
        return
    }

    psBlob->Release()
    vsBlob->Release()
    return true
}


DestroyShader :: proc(renderCtx: ^RenderContext, handle: ShaderHandle, freeHandle := true) {
    shader, ok := GetElementPtr(renderCtx.shaders, handle)
    if ok == false {
        return
    }

    if shader.vertexShader != nil {
        shader.vertexShader->Release()
    }

    if shader.pixelShader != nil {
        shader.pixelShader->Release()
    }

    if freeHandle {
        shader.vertexShader = nil
        shader.pixelShader = nil
        FreeSlot(&renderCtx.shaders, handle)
    }
}

// FRAMEBUFFER

FramebufferBackend :: struct {
    renderTargetView: ^d3d11.IRenderTargetView,
    textureView: ^d3d11.IShaderResourceView,
}

InitFramebuffer :: proc(ctx: ^RenderContext, framebuffer: ^Framebuffer) {
    desc := d3d11.TEXTURE2D_DESC {
        Width      = cast(u32) framebuffer.width,
        Height     = cast(u32) framebuffer.height,
        MipLevels  = 1,
        ArraySize  = 1,
        Format     = .R32G32B32A32_FLOAT,
        SampleDesc = {Count = 1},
        Usage      = .DEFAULT,
        BindFlags  = {.SHADER_RESOURCE, .RENDER_TARGET},
    }

    d3dTexture: ^d3d11.ITexture2D
    ctx.device->CreateTexture2D(&desc, nil, &d3dTexture)

    ctx.device->CreateRenderTargetView(d3dTexture, nil, &framebuffer.renderTargetView)
    ctx.device->CreateShaderResourceView(d3dTexture, nil, &framebuffer.textureView)

    d3dTexture->Release()
}

DeinitFramebuffer :: proc(framebuffer: ^Framebuffer) {
    if framebuffer.renderTargetView != nil {
        framebuffer.renderTargetView->Release()
        framebuffer.renderTargetView = nil
    }

    if framebuffer.textureView != nil {
        framebuffer.textureView->Release()
        framebuffer.textureView = nil
    }
}


// UNIFORM BUFFER

GPUBufferBackend :: struct {
    d3dBuffer: ^d3d11.IBuffer,
}

BackendInitGPUBuffer :: proc(buff: ^GPUBuffer) {
    constBuffDesc := d3d11.BUFFER_DESC {
        ByteWidth = cast(u32) buff.dataLen,
        Usage = .DYNAMIC,
        BindFlags = { .CONSTANT_BUFFER },
        CPUAccessFlags = { .WRITE },
    }

    renderCtx.device->CreateBuffer(&constBuffDesc, nil, &buff.d3dBuffer)
}

BackendUpdateBufferData :: proc(buff: ^GPUBuffer) {
    mapped: d3d11.MAPPED_SUBRESOURCE
    res := renderCtx.deviceContext->Map(buff.d3dBuffer, 0, .WRITE_DISCARD, nil, &mapped)
    if res == 0 {
        mem.copy(mapped.pData, buff.dataPtr, buff.dataLen)
    }
    else {
        fmt.eprintln("Cannot Updload data of uniform buffer. Error Code:", res)
    }
    renderCtx.deviceContext->Unmap(buff.d3dBuffer, 0)
}