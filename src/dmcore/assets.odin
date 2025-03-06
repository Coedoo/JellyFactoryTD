package dmcore

import "core:fmt"
import "core:strings"
import "core:os"

when ODIN_OS != .JS {
    ASSETS_ROOT :: #config(ASSET_ROOT, "../assets/")
}
else {
    ASSETS_ROOT :: #config(ASSET_ROOT, "./assets/")
}

TextureAssetDescriptor :: struct {
    filter: TextureFilter
}

ShaderAssetDescriptor :: struct {
}

FontAssetDescriptor :: struct {
    fontType: FontType,
    fontSize: int,
}

SoundAssetDescriptor :: struct {
}

RawFileAssetDescriptor :: struct {
}

AssetDescriptor :: union {
    TextureAssetDescriptor,
    ShaderAssetDescriptor,
    FontAssetDescriptor,
    SoundAssetDescriptor,
    RawFileAssetDescriptor,
}

AssetData :: struct {
    fileName: string,
    alias: string,

    fileData: []u8,

    lastWriteTime: os.File_Time,

    handle: Handle,

    descriptor: AssetDescriptor
}

LoadEntry :: struct {
    key: string,
    name: string,
}

Assets :: struct {
    assetsMap: map[string]AssetData,

    loadQueue: [dynamic]LoadEntry
}

RegisterAsset :: proc(fileName: string, desc: AssetDescriptor, key: string = "") {
    RegisterAssetCtx(assets, fileName, desc, key)
}

RegisterAssetCtx :: proc(assets: ^Assets, fileName: string, desc: AssetDescriptor, key: string = "") {
    if fileName in assets.assetsMap {
        fmt.eprintln("Duplicated asset file name:", fileName, ". Skipping...")
        return
    }


    clonedName := strings.clone(fileName)

    clonedKey: string
    if key == "" {
        clonedKey = clonedName
    }
    else {
        clonedKey = strings.clone(key)
    }

    assets.assetsMap[clonedKey] = AssetData {
        fileName = clonedName,
        descriptor = desc,
    }

    append(&assets.loadQueue, LoadEntry{clonedKey, clonedName})
}

GetAssetData :: proc(fileName: string) -> ^AssetData {
    return GetAssetDataCtx(assets, fileName)
}

GetAssetDataCtx :: proc(assets: ^Assets, fileName: string) -> ^AssetData {
    return &assets.assetsMap[fileName]
}

GetAsset :: proc(fileName: string) -> Handle {
    return GetAssetCtx(assets, fileName)
}

GetAssetCtx :: proc(assets: ^Assets, fileName: string) -> Handle {
    return assets.assetsMap[fileName].handle
}

GetTextureAsset :: proc(fileName: string) -> TexHandle {
    return cast(TexHandle) GetAssetCtx(assets, fileName)
}

GetTextureAssetCtx :: proc(assets: ^Assets, fileName: string) -> TexHandle {
    return cast(TexHandle) GetAssetCtx(assets, fileName)
}

// @TODO: ReloadAsset

ReleaseAssetData :: proc(fileName: string) {
    ReleaseAssetDataCtx(assets, fileName)
}

ReleaseAssetDataCtx :: proc(assets: ^Assets, fileName: string) {
    assetData, ok := &assets.assetsMap[fileName]
    if ok && assetData.fileData != nil {
        delete(assetData.fileData)
        assetData.fileData = nil
    }
}

CheckAndHotReloadAssets :: proc(assets: ^Assets) {
    for name, &asset in &assets.assetsMap {
        switch desc in asset.descriptor {
        case FontAssetDescriptor, SoundAssetDescriptor:
            continue

        case TextureAssetDescriptor:
            path := strings.concatenate({ASSETS_ROOT, name}, context.temp_allocator)
            assetNewTime, err := os.last_write_time_by_name(path)
            if err == os.ERROR_NONE && assetNewTime > asset.lastWriteTime {
                data, ok := os.read_entire_file(path, context.temp_allocator)
                if ok {
                    // image, pngErr := png.load_from_bytes(data, allocator = context.temp_allocator)
                    // if pngErr == nil {
                    //     tex := GetTextureCtx(engineData.renderCtx, auto_cast asset.handle)
                    //     _ReleaseTexture(tex)
                    //     _InitTexture(engineData.renderCtx, tex, image.pixels.buf[:], image.width, image.height, image.channels, desc.filter)

                    //     asset.lastWriteTime = assetNewTime
                    // }
                }
            }

        case ShaderAssetDescriptor:
            path := strings.concatenate({ASSETS_ROOT, name}, context.temp_allocator)
            assetNewTime, err := os.last_write_time_by_name(path)
            if err == os.ERROR_NONE && assetNewTime > asset.lastWriteTime {
                data, ok := os.read_entire_file(path, context.temp_allocator)
                if ok {
                    handle := ShaderHandle(asset.handle)
                    DestroyShader(renderCtx, handle, freeHandle = false)

                    source := strings.string_from_ptr(raw_data(data), len(data))

                    shader, _ := GetElementPtr(renderCtx.shaders, handle)
                    InitShaderSource(renderCtx, shader, source)

                    asset.lastWriteTime = assetNewTime
                    fmt.println("Reloading shader:", name)
                }
            }
        case RawFileAssetDescriptor: // @TODO: I'm not sure how to handle that, or even if I should?
        }

    }
}