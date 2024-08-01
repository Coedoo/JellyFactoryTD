package dmcore

import "core:mem"
import "core:os"
import "core:fmt"
import "core:unicode/utf8"

import "core:encoding/base64"

import math "core:math/linalg/glsl"
import coreMath "core:math"

GLYPH_RANGE_LOW :: 32
GLYPH_RANGE_HIGH :: 383
GLYPH_COUNT :: GLYPH_RANGE_HIGH - GLYPH_RANGE_LOW

GlyphData :: struct {
    codepoint: rune,

    pixelWidth: int,
    pixelHeight: int,

    atlasPos:  v2,
    atlasSize: v2,

    offset: v2,

    advanceX: int,
}

FontType :: enum {
    Bitmap,
    SDF,
}

KerningKey :: struct {
    rune1, rune2: rune
}

KerningTable :: map[KerningKey]f32

Font :: struct {
    size: int,
    type: FontType,

    ascent:  f32,
    descent: f32,
    lineGap: f32,

    lineHeight: f32,

    atlas: TexHandle,
    glyphData: [GLYPH_COUNT]GlyphData,
    kerningTable: KerningTable,
}


GetCodepointIndex :: proc(codepoint: rune) -> int {
    if codepoint > GLYPH_RANGE_HIGH {
        return -1;
    }

    return int(codepoint) - GLYPH_RANGE_LOW
}

KerningLookup :: proc(font: Font, a, b: rune) -> f32  {
    key := KerningKey{
        rune1 = a,
        rune2 = b,
    }

    // if there is no key, map will return 0 so it's all good
    return font.kerningTable[key]
}

DrawTextCentered :: proc(ctx: ^RenderContext, str: string, font: Font, position: v2, fontSize: int = 0,
    color := color{1, 1, 1, 1}) {
    size := MeasureText(str, font, fontSize)
    pos := position - size / 2

    DrawText(ctx, str, font, pos, fontSize, color)
}

DrawText :: proc(ctx: ^RenderContext, str: string, font: Font, position: v2, fontSize: int = 0,
    color := color{1, 1, 1, 1}) {


    fontSize := fontSize
    if fontSize == 0 do fontSize = font.size

    scale := f32(fontSize) / f32(font.size)

    posX := position.x
    posY := position.y + font.lineHeight * scale

    // @TODO: I can cache atlas size
    texSize := GetTextureSize(font.atlas)
    fontAtlasSize := ToV2(texSize)

    ///// DEBUG
    // size := MeasureText(str, font, fontSize)
    // DrawBox2D(ctx, position + size / 2, size, true)
    ////

    shader := ctx.defaultShaders[.SDFFont] if font.type == .SDF else ctx.defaultShaders[.ScreenSpaceRect]

    runes := utf8.string_to_runes(str, context.temp_allocator)
    for c, i in runes {
        if c == '\n' {
            posY += font.lineHeight * scale
            posX = position.x

            continue
        }

        index := GetCodepointIndex(c)
        glyphData := font.glyphData[index]

        pos  := v2{posX, posY} + glyphData.offset * scale
        size := v2{f32(glyphData.pixelWidth), f32(glyphData.pixelHeight)}
        dest := Rect{pos.x, pos.y, size.x * scale, size.y * scale}

        texPos  := ToIv2(glyphData.atlasPos  * fontAtlasSize)
        texSize := ToIv2(glyphData.atlasSize * fontAtlasSize)
        src := RectInt{texPos.x, texPos.y, texSize.x, texSize.y}

        DrawRect(ctx, font.atlas, src, dest, shader, v2{0, 0}, color)

        advance := glyphData.advanceX if glyphData.advanceX != 0 else glyphData.pixelWidth
        posX += f32(advance) * scale

        if i + 1 < len(runes) {
            posX += KerningLookup(font, c, runes[i+1])
        }
    }
}


LoadDefaultFont :: proc(renderCtx: ^RenderContext) -> Font {
    // @NOTE: I'm not sure that's strong enough check
    if font.atlas.slotIndex == 0 {
        atlasData := base64.decode(ATLAS, allocator = context.temp_allocator)
        font.atlas = CreateTexture(renderCtx, atlasData, ATLAS_SIZE, ATLAS_SIZE, 4, font.type == .SDF ? .Bilinear : .Point)
    }

    return font
}

MeasureText :: proc(str: string, font: Font, fontSize: int = 0) -> v2 {
    fontSize := fontSize

    if fontSize == 0 do fontSize = font.size
    scale := f32(fontSize) / f32(font.size)

    posX := f32(0)
    lines := 1

    width := f32(0)
    height := 0

    for c, i in str {
        if c == '\n' {
            width = max(width, posX)

            posX = 0
            lines += 1

            continue
        }

        index := GetCodepointIndex(c)
        glyphData := font.glyphData[index]

        advance := glyphData.advanceX if glyphData.advanceX != 0 else glyphData.pixelWidth
        posX += f32(advance)
    }

    width = max(width, posX)
    return {width, f32(lines) * font.lineHeight - font.descent} * scale
}
