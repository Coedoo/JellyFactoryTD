//+build windows
package dmcore

import d3d11 "vendor:directx/d3d11"
import d3d "vendor:directx/d3d_compiler"

import "core:fmt"


_Shader :: struct {
    vertexShader: ^d3d11.IVertexShader,
    pixelShader: ^d3d11.IPixelShader,
}

CompileShaderSource :: proc(renderCtx: ^RenderContext, source: string) -> ShaderHandle {
    ctx := cast(^RenderContext_d3d) renderCtx

    shader := CreateElement(&ctx.shaders)

    error: ^d3d11.IBlob

    vsBlob: ^d3d11.IBlob
    defer vsBlob->Release()

    hr := d3d.Compile(raw_data(source), len(source), "shaders.hlsl", nil, nil, 
                      "vs_main", "vs_5_0", 0, 0, &vsBlob, &error)

    if hr < 0 {
        fmt.println(transmute(cstring) error->GetBufferPointer())
        error->Release()

        return {}
    }

    ctx.device->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), 
                                         nil, &shader.backend.vertexShader)

    psBlob: ^d3d11.IBlob
    defer psBlob->Release()

    hr = d3d.Compile(raw_data(source), len(source), "shaders.hlsl", nil, nil,
                     "ps_main", "ps_5_0", 0, 0, &psBlob, &error)

    if hr < 0 {
        fmt.println(transmute(cstring) error->GetBufferPointer())
        error->Release()

        return {}
    }

    ctx.device->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), 
                                        nil, &shader.backend.pixelShader)

    return shader.handle
}

