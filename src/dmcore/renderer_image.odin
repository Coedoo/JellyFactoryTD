package dmcore

import "core:os"
import "core:fmt"
// import "core:image/png"

import stbi "vendor:stb/image"

TextureFilter :: enum {
    Point,
    Bilinear,
    Mip,
}

Texture :: struct {
    handle: TexHandle,

    // @NOTE: I'm not sure if int is a good type here, since
    // it wil be 32 bits on WASM
    // backendData: int,
    using backend: TextureBackend,

    filter: TextureFilter,

    width: i32,
    height: i32,
}

// GetTexture :: proc(handle: TexHandle) -> (^Texture {
//     return GetTextureCtx(renderCtx, handle)
// }

// GetTextureCtx :: proc(renderCtx: ^RenderContext, handle: TexHandle) -> (^Texture, bool) {
//     return GetElementPtr(renderCtx.textures, handle)
// }

GetTextureSize :: proc(handle: TexHandle) -> iv2 {
    info := GetElement(renderCtx.textures, handle)
    return {info.width, info.height}
}

LoadTextureFromFile :: proc(filePath: string, filter := TextureFilter.Point) -> TexHandle {
    return LoadTextureFromFileCtx(renderCtx, filePath, filter)
}

LoadTextureFromFileCtx :: proc(renderCtx: ^RenderContext, filePath:string, filter := TextureFilter.Point) -> TexHandle {
    data, ok := os.read_entire_file(filePath, context.temp_allocator)

    if ok == false {
        fmt.eprintf("Failed to open file: %v\n", filePath)
        return {}
    }

    return LoadTextureFromMemoryCtx(renderCtx, data)
}

LoadTextureFromMemory :: proc(data: []u8, filter := TextureFilter.Point) -> TexHandle {
    return LoadTextureFromMemoryCtx(renderCtx, data, filter)
}

LoadTextureFromMemoryCtx :: proc(renderCtx: ^RenderContext, data: []u8, filter := TextureFilter.Point) -> TexHandle {
    // @TODO: support different formats
    // image, err := png.load_from_bytes(data, allocator = context.temp_allocator)
    // if err != nil {
    //     fmt.eprintf("Failed to load texture from memory. Error:", err)
    //     return {}
    // }

    width, height, channels: i32
    imageData := stbi.load_from_memory(
        &data[0],
        cast(i32) len(data),
        &width,
        &height,
        &channels,
        4,
    )

    defer stbi.image_free(imageData)


    tex := CreateElement(&renderCtx.textures)
    _InitTexture(renderCtx, tex, imageData[:width * height * 4], int(width), int(height), int(channels), filter)
    // _InitTexture(renderCtx, tex, image.pixels.buf[:], image.width, image.height, image.channels, filter)

    // fmt.println(tex)

    return tex.handle
}

CreateTexture :: proc(renderCtx: ^RenderContext, rawData: []u8, width, height, channels: int, filter: TextureFilter) -> TexHandle {

    tex := CreateElement(&renderCtx.textures)
    _InitTexture(renderCtx, tex, rawData, width, height, channels, filter)

    return tex.handle
}

////////////////////////////////////
/// Sprites
///////////////////////////////////
Axis :: enum {
    Horizontal,
    Vertical,
}

Sprite :: struct {
    texture: TexHandle,

    origin: v2,

    texturePos: iv2,
    textureSize: iv2,

    tint: color,

    flipX, flipY: bool,

    scale: f32,

    frames: i32,
    currentFrame: i32,
    animDirection: Axis,
}

CreateSprite :: proc {
    CreateSpriteFromTexture,
    CreateSpriteFromTextureRect,
    CreateSpriteFromTexturePosSize,
}

CreateSpriteFromTexture :: proc(texture: TexHandle) -> Sprite {
    size := GetTextureSize(texture)
    return {
        texture = texture,

        texturePos  = {0, 0},
        textureSize = size,

        origin = {0.5, 0.5},

        tint = {1, 1, 1, 1},

        scale = 1,
    }
}

CreateSpriteFromTextureRect :: proc(texture: TexHandle, rect: RectInt, 
    origin := v2{0.5, 0.5},
    tint := color{1, 1, 1, 1},
    scale := f32(1),
    frames := i32(1),
    flipX := false,
    flipY := false
) -> Sprite
{
    return {
        texture = texture,

        texturePos  = {rect.x, rect.y},
        textureSize = {rect.width, rect.height},

        origin = origin,

        tint = tint,

        flipX = flipX,
        flipY = flipY,

        scale = scale,
        frames = frames,
    }
}

CreateSpriteFromTexturePosSize :: proc(texture: TexHandle, texturePos: iv2, atlasSize: iv2) -> Sprite {
    return {
        texture = texture,

        texturePos  = texturePos,
        textureSize = atlasSize,

        origin = {0.5, 0.5},

        tint = {1, 1, 1, 1},

        scale = 1,
    }
}

AnimateSprite :: proc(sprite: ^Sprite, time: f32, frameTime: f32) {
    t := cast(i32) (time / frameTime)
    t = t%sprite.frames

    sprite.currentFrame = t
}

GetSpriteSize :: proc(sprite: Sprite) -> v2 {
    sizeX := sprite.scale
    sizeY := f32(sprite.textureSize.y) / f32(sprite.textureSize.x) * sizeX

    return {sizeX, sizeY}
}


SpriteAtlas :: struct {
    texAssetPath: string,
    texture: TexHandle `json:"-"`,
    cellSize: iv2,
    spacing: iv2,
    padding: iv2,
}

GetCellsCount :: proc(atlas: SpriteAtlas) -> iv2 {
    size := GetTextureSize(atlas.texture)
    return size / atlas.cellSize
}

GetSprite :: proc(atlas: SpriteAtlas, cell: iv2, 
    origin := v2{0.5, 0.5}, 
    cellSize := iv2{1, 1}) -> Sprite
{
    srcRect := GetSpriteRect(atlas, cell, cellSize)
    return CreateSprite(atlas.texture, srcRect)
}

GetSpriteRect :: proc(atlas: SpriteAtlas, cell: iv2,
    cellSize := iv2{1, 1}) -> RectInt
{
    pos  := (atlas.cellSize * cell 
             + atlas.padding 
             + (atlas.spacing * cell))

    size := atlas.cellSize * cellSize

    return {pos.x, pos.y, size.x, size.y}
}