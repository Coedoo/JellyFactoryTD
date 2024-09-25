#+build windows
package dmcore

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import d3d "vendor:directx/d3d_compiler"

// _CreateTexture :: proc(renderCtx: ^RenderContext, rawData: []u8, width, height, channels: int, filter: TextureFilter) -> TexHandle {
//     ctx := cast(^RenderContext_d3d) renderCtx

//     tex := CreateElement(ctx.textures)
//     InitTexture(tex, rawData, width, height, channels, ctx, filter)

//     return tex.handle
// }

TextureBackend :: struct {
    textureView: ^d3d11.IShaderResourceView,
}

_InitTexture :: proc(ctx: ^RenderContext, tex: ^Texture, rawData: []u8, width, height, channels: int, filter: TextureFilter)
{
    format: dxgi.FORMAT
    switch channels { 
    case 1: format = .R8_UNORM
    case 2: format = .R8G8_UNORM
    // @TODO: add expansion to 4 channels for 3 channels textures
    // case 3: format = format = .R8G8B8A8_UNORM_SRGB 
    case 4: format = .R8G8B8A8_UNORM_SRGB
    case: panic("Unsupported image channels count")
    }

    texDesc := d3d11.TEXTURE2D_DESC {
        Width      = u32(width),
        Height     = u32(height),
        MipLevels  = 1,
        ArraySize  = 1,
        Format     = format,
        SampleDesc = {Count = 1},
        Usage      = .IMMUTABLE,
        BindFlags  = {.SHADER_RESOURCE},
    }


    texData := d3d11.SUBRESOURCE_DATA{
        pSysMem     = &rawData[0],
        SysMemPitch = u32(width * channels),
    }

    d3dTexture: ^d3d11.ITexture2D
    textureView: ^d3d11.IShaderResourceView

    ctx.device->CreateTexture2D(&texDesc, &texData, &d3dTexture)
    ctx.device->CreateShaderResourceView(d3dTexture, nil, &textureView)

    d3dTexture->Release()

    tex.textureView = textureView

    // samplerDesc := d3d11.SAMPLER_DESC{
    //     // Filter         = .MIN_MAG_MIP_POINT,
    //     // Filter         = .MIN_MAG_MIP_LINEAR,
    //     AddressU       = .WRAP,
    //     AddressV       = .WRAP,
    //     AddressW       = .WRAP,
    //     ComparisonFunc = .NEVER,
    // }

    // switch filter {
    // case .Point: samplerDesc.Filter = .MIN_MAG_MIP_POINT
    // case .Bilinear: samplerDesc.Filter = .MIN_MAG_MIP_LINEAR
    // case .Mip:
    //     panic("Implement Me!")
    // }

    // ctx.device->CreateSamplerState(&samplerDesc, &tex.samplerState)

    tex.filter = filter
    tex.width  = i32(width)
    tex.height = i32(height)
}

_ReleaseTexture :: proc(texture: ^Texture) {
    texture.textureView->Release()
}