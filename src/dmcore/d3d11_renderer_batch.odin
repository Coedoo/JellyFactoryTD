#+build windows
package dmcore

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import d3d "vendor:directx/d3d_compiler"

import "core:c/libc"

BatchConstants :: struct #align(16) {
    screenSize: [2]f32,
    oneOverAtlasSize: [2]f32,
}

_RectBatch :: struct {
    // TODO: can probably abstract it to GPU buffer
    d3dBuffer: ^d3d11.IBuffer, // rect buffer
    SRV:       ^d3d11.IShaderResourceView, // 

    constBuffer: ^d3d11.IBuffer,
}

InitRectBatch :: proc(renderCtx: ^RenderContext, batch: ^RectBatch, count: int) {
    rectBufferDesc := d3d11.BUFFER_DESC {
        ByteWidth = u32(count) * size_of(RectBatchEntry),
        Usage     = .DYNAMIC,
        BindFlags = { .SHADER_RESOURCE },
        CPUAccessFlags = { .WRITE },
        MiscFlags = {.BUFFER_STRUCTURED},
        StructureByteStride = size_of(RectBatchEntry),
    }

    renderCtx.device->CreateBuffer(&rectBufferDesc, nil, &batch.backend.d3dBuffer)

    rectSRVDesc := d3d11.SHADER_RESOURCE_VIEW_DESC {
        Format = .UNKNOWN,
        ViewDimension = .BUFFER,
    }

    rectSRVDesc.Buffer.NumElements = u32(count)

    renderCtx.device->CreateShaderResourceView(batch.backend.d3dBuffer, &rectSRVDesc, &batch.backend.SRV)

    constBuffDesc := d3d11.BUFFER_DESC {
        ByteWidth = size_of(BatchConstants),
        Usage = .DYNAMIC,
        BindFlags = { .CONSTANT_BUFFER },
        CPUAccessFlags = { .WRITE },
    }

    renderCtx.device->CreateBuffer(&constBuffDesc, nil, &batch.backend.constBuffer)

    batch.buffer = make([]RectBatchEntry, count)
    batch.maxCount = count
}

DrawBatch :: proc(ctx: ^RenderContext, batch: ^RectBatch) {
    if batch.count == 0 {
        return
    }

    screenSize := [2]f32 {
         2 / f32(ctx.frameSize.x),
        -2 / f32(ctx.frameSize.y),
    }

    // @TODO: better shader validation:
    assert(batch.shader.gen != 0)
    texture := GetElement(ctx.textures, batch.texture)

    oneOverAtlasSize := [2]f32 {
        1 / f32(texture.width),
        1 / f32(texture.height),
    }

    ////

    ctx.deviceContext->IASetPrimitiveTopology(.TRIANGLESTRIP)

    shader := GetElement(ctx.shaders, batch.shader)

    ctx.deviceContext->VSSetShader(shader.backend.vertexShader, nil, 0)

    mapped: d3d11.MAPPED_SUBRESOURCE
    res := ctx.deviceContext->Map(batch.backend.constBuffer, 0, .WRITE_DISCARD, nil, &mapped)

    val := cast(^BatchConstants) mapped.pData
    val.screenSize = screenSize
    val.oneOverAtlasSize = oneOverAtlasSize

    // if batch.camera != nil {
        // val.VP = GetVPMatrix(&ctx.camera)
    // }

    ctx.deviceContext->Unmap(batch.backend.constBuffer, 0)

    ctx.deviceContext->VSSetShaderResources(0, 1, &batch.backend.SRV)
    ctx.deviceContext->VSSetConstantBuffers(1, 1, &batch.backend.constBuffer)

    // Create Sampler State
    // According to the documentation, creating new sampler state with the same
    // SamplerDesc as one created before, will return already existing sampler state
    // So in theory, I don't have to keep track of them
    // But I don't know the performance cost yet
    // @TODO @PERFORMANCE: check
    samplerDesc := d3d11.SAMPLER_DESC{
        // Filter         = .MIN_MAG_MIP_POINT,
        // Filter         = .MIN_MAG_MIP_LINEAR,
        AddressU       = .CLAMP,
        AddressV       = .CLAMP,
        AddressW       = .CLAMP,
        ComparisonFunc = .NEVER,
    }

    switch texture.filter {
    case .Point: samplerDesc.Filter = .MIN_MAG_MIP_POINT
    case .Bilinear: samplerDesc.Filter = .MIN_MAG_MIP_LINEAR
    case .Mip:
        panic("Implement Me!")
    }

    samplerState: ^d3d11.ISamplerState
    ctx.device->CreateSamplerState(&samplerDesc, &samplerState)

    // textureView := transmute(^d3d11.IShaderResourceView) texture.backendData

    ctx.deviceContext->PSSetShader(shader.backend.pixelShader, nil, 0)
    ctx.deviceContext->PSSetShaderResources(1, 1, &texture.textureView)
    ctx.deviceContext->PSSetSamplers(0, 1, &samplerState)
    ctx.deviceContext->PSSetConstantBuffers(1, 1, &batch.backend.constBuffer)

    msr : d3d11.MAPPED_SUBRESOURCE
    ctx.deviceContext->Map(batch.backend.d3dBuffer, 0, .WRITE_DISCARD, nil, &msr)

    libc.memcpy(msr.pData, &batch.buffer[0], uint(size_of(RectBatchEntry) * batch.count))

    ctx.deviceContext->Unmap(batch.backend.d3dBuffer, 0)

    ctx.deviceContext->DrawInstanced(4, u32(batch.count), 0, 0);

    batch.count = 0
}