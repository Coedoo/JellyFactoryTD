package dmcore

import "core:mem"
import "core:os"
import "core:fmt"
import "core:unicode/utf8"


import "core:strings"

import math "core:math/linalg/glsl"
import coreMath "core:math"

import stbtt "vendor:stb/truetype"
import stbrp "vendor:stb/rect_pack"

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

FontHandle :: Handle
Font :: struct {
    handle: FontHandle,

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

DrawTextCentered :: proc(str: string, position: v2,
    fontHandle: FontHandle = {0, 0},
    fontSize: f32 = 0,
    color := color{1, 1, 1, 1})
{
    str := str
    font := GetElement(renderCtx.fonts, fontHandle)
    sizeY := MeasureText(str, font, fontSize).y

    scale := fontSize / f32(font.size)

    line := 0
    for {
        idx := strings.index_rune(str, '\n')
        doContinue := true

        if idx == -1 {
            idx = len(str) - 1
            doContinue = false
        }

        toDraw := str[:idx + 1]
        size := MeasureText(toDraw, font, fontSize)
        drawPos := v2{position.x - size.x / 2, position.y + f32(line) * font.lineHeight - sizeY / 2}

        DrawText(toDraw, drawPos, fontHandle, fontSize, color)

        line += 1
        str = str[idx + 1:]

        if doContinue == false {
            break
        }
    }
}

DrawText :: proc(str: string, position: v2,
    fontHandle: FontHandle = {0, 0},
    fontSize: f32 = 0,
    color := color{1, 1, 1, 1})
{
    font := GetElement(renderCtx.fonts, fontHandle)

    fontSize := fontSize
    if fontSize == 0 do fontSize = f32(font.size)

    scale := fontSize / f32(font.size)


    // // @TODO: I can cache atlas size
    fontAtlasSize := ToV2(GetTextureSize(font.atlas))

    yDir: f32 = renderCtx.inScreenSpace ? 1 : -1

    ///// DEBUG
    // size := MeasureText(str, font, fontSize)
    // DrawDebugBox(renderCtx, position + size / 2 * {1, yDir}, size, renderCtx.inScreenSpace, color = RED)
    ////

    shader := renderCtx.defaultShaders[.SDFFont] if font.type == .SDF else renderCtx.defaultShaders[.Sprite]

    posX := position.x
    posY := position.y + font.lineHeight * scale * yDir

    runes := utf8.string_to_runes(str, context.temp_allocator)
    for c, i in runes {
        if c == 0 {
            break
        }

        if c == '\n' {
            posY += font.lineHeight * scale * yDir
            // posY += font.lineHeight * scale
            posX = position.x

            continue
        }

        index := GetCodepointIndex(c)
        glyphData := font.glyphData[index]

        texPos  := ToIv2(glyphData.atlasPos  * fontAtlasSize)
        texSize := ToIv2(glyphData.atlasSize * fontAtlasSize)

        pY := posY
        if renderCtx.inScreenSpace == false {
            pY -= f32(glyphData.pixelHeight) * scale;
        }

        finalPos := v2{posX, pY} + {0, glyphData.offset.y * scale * yDir}
        size := v2{f32(glyphData.pixelWidth), f32(glyphData.pixelHeight)} * scale
        texSource := RectInt{texPos.x, texPos.y, texSize.x, texSize.y}
        // tint = color
        // pivot = {0, 0}

        // cmd.texture = font.atlas
        // cmd.shader =  shader

        // append(&renderCtx.commandBuffer.commands, cmd)

        DrawRectSrcDst(font.atlas, texSource, {finalPos.x, finalPos.y, size.x, size.y}, shader, {0, 0}, 0, color)

        advance := glyphData.advanceX if glyphData.advanceX != 0 else glyphData.pixelWidth
        posX += f32(advance) * scale

        if i + 1 < len(runes) {
            posX += KerningLookup(font, c, runes[i+1]) * scale
        }
    }
}


// LoadDefaultFont :: proc(renderCtx: ^RenderContext) -> Font {
//     // @NOTE: I'm not sure that's strong enough check
//     if font.atlas.slotIndex == 0 {
//         atlasData := base64.decode(ATLAS, allocator = context.temp_allocator)
//         font.atlas = CreateTexture(renderCtx, atlasData, ATLAS_SIZE, ATLAS_SIZE, 4, font.type == .SDF ? .Bilinear : .Point)
//     }

//     return font
// }

MeasureText :: proc {
    MeasureTextFont,
    MeasureTextHandle
}

MeasureTextHandle :: proc(str: string, font: FontHandle, fontSize: f32 = 0) -> v2 {
    font := GetElement(renderCtx.fonts, font)
    return MeasureTextFont(str, font, fontSize)
}

MeasureTextFont :: proc(str: string, font: Font, fontSize: f32 = 0) -> v2 {
    fontSize := fontSize

    if fontSize == 0 do fontSize = f32(font.size)
    scale := f32(fontSize) / f32(font.size)

    posX := f32(0)
    lines := 1

    width := f32(0)
    height := 0

    runes := utf8.string_to_runes(str, context.temp_allocator)
    for c, i in runes {
        if c == 0 {
            continue
        }

        if c == '\n' {
            width = max(width, posX)

            posX = 0
            lines += 1

            continue
        }

        index := GetCodepointIndex(c)
        glyphData := font.glyphData[index]

        if i + 1 < len(runes) {
            if runes[i + 1] == '\n' {
                idx := GetCodepointIndex(runes[i + 1])
                posX += f32(font.glyphData[idx].pixelWidth)
            }
            else {
                advance := glyphData.advanceX if glyphData.advanceX != 0 else glyphData.pixelWidth
                posX += f32(advance)
            }
        }
        else {
            posX += f32(glyphData.pixelWidth)
        }

        if i + 1 < len(runes) {
            posX += KerningLookup(font, c, runes[i+1])
        }
    }

    width = max(width, posX)
    return {width, f32(lines) * font.lineHeight - font.descent} * scale
}



LoadFontSDF :: proc(renderCtx: ^RenderContext, data: []u8, fontSize: int) -> FontHandle {
    // fileData, ok := os.read_entire_file(fileName, context.temp_allocator)
    // if ok == false {
    //     fmt.eprintf("Failed To Load File: %v !!\n", fileName)
    //     return {}
    // }

    font: Font
    bitmap, bitmapSize := InitFontSDF(&font, data, fontSize)

    font.atlas = CreateTexture(renderCtx, mem.slice_to_bytes(bitmap), int(bitmapSize), int(bitmapSize), 4, .Bilinear)

    handle := AppendElement(&renderCtx.fonts, font)
    return handle
}

InitFontSDF :: proc(font: ^Font, data: []u8, fontSize: int) -> (bitmap: []i32, bitmapSize: i32) {
    padding :: 3
    onEdgeValue :: 128
    distanceScale :: 32

    // fileData, ok := os.read_entire_file(fileName, context.temp_allocator)
    // if ok == false {
    //     fmt.eprintf("Failed To Load File: %v !!\n", fileName)
    //     return
    // }

    fontInfo: stbtt.fontinfo
    if stbtt.InitFont(&fontInfo, raw_data(data), 0) == false {
        // @TODO: add name to font for easier recognition
        fmt.eprintf("Failed To Init a Font: %v !!\n")
        return
    }

    font.size = fontSize
    font.type = .SDF

    scaleFactor := stbtt.ScaleForPixelHeight(&fontInfo, f32(fontSize))

    ascent, descent, lineGap: i32
    stbtt.GetFontVMetrics(&fontInfo, &ascent, &descent, &lineGap)

    font.ascent  = f32(ascent) * scaleFactor
    font.descent = f32(descent) * scaleFactor
    font.lineGap = f32(lineGap) * scaleFactor
    font.lineHeight = font.ascent - font.descent + font.lineGap


    bitmaps: [GLYPH_COUNT][^]byte
    defer for b in bitmaps {
        stbtt.FreeSDF(b, nil)
    }

    area: i32
    for i in GLYPH_RANGE_LOW..<GLYPH_RANGE_HIGH {
        width, height: i32
        xoff, yoff: i32

        bitmaps[i - GLYPH_RANGE_LOW] = stbtt.GetCodepointSDF(
                                                &fontInfo, 
                                                scaleFactor, 
                                                i32(i), 
                                                padding, 
                                                onEdgeValue, 
                                                distanceScale, 
                                                &width, 
                                                &height, 
                                                &xoff, 
                                                &yoff
                                            )

        advanceX: i32
        stbtt.GetCodepointHMetrics(&fontInfo, rune(i), &advanceX, nil)

        glyph := GlyphData {
            codepoint = rune(i),
            pixelWidth  = int(width),
            pixelHeight = int(height),

            offset = {f32(xoff), f32(yoff)},
            advanceX = int(f32(advanceX) * scaleFactor),
        }

        // fmt.println(glyph.codepoint, glyph.offset)

        idx := GetCodepointIndex(rune(i))
        font.glyphData[idx] = glyph

        area += width * height
    }

    sqrSurface := int(math.sqrt(f32(area)) + 1)
    bitmapSize = cast(i32) coreMath.next_power_of_two(sqrSurface)

    rpCtx := new(stbrp.Context, context.temp_allocator)
    nodes := make([]stbrp.Node, GLYPH_COUNT, context.temp_allocator)
    rects := make([]stbrp.Rect, GLYPH_COUNT, context.temp_allocator)

    stbrp.init_target(rpCtx, bitmapSize, bitmapSize, raw_data(nodes), i32(len(nodes)))

    for g, i in font.glyphData {
        rects[i].id = i32(g.codepoint)
        rects[i].w = cast(stbrp.Coord) g.pixelWidth
        rects[i].h = cast(stbrp.Coord) g.pixelHeight
    }

    stbrp.pack_rects(rpCtx, raw_data(rects), i32(len(rects)))

    bitmap = make([]i32, bitmapSize * bitmapSize, context.temp_allocator)
    for r, i in rects {
        if r.was_packed == false {
            fmt.eprintln("Failed To pack codepoint:", rune(r.id), "(", r.id, ")")
            continue
        }

        if bitmaps[i] == nil {
            continue
        }

        x := i32(r.x)
        y := i32(r.y)
        w := i32(font.glyphData[i].pixelWidth)
        h := i32(font.glyphData[i].pixelHeight)

        for bitmapX in 0..<w {
            for bitmapY in 0..<h {
                atlasX := x + bitmapX
                atlasY := y + bitmapY

                bitmapIdx := bitmapY * w + bitmapX
                atlasIdx := atlasY * bitmapSize + atlasX

                b := bitmaps[i]
                v := b[bitmapIdx]

                bitmap[atlasIdx] = transmute(i32) [4]u8{255, 255, 255, v}
            }
        }

        font.glyphData[i].atlasPos = {f32(r.x) / f32(bitmapSize), f32(r.y) / f32(bitmapSize)}
        font.glyphData[i].atlasSize = {f32(w) / f32(bitmapSize), f32(h) / f32(bitmapSize)}
    }

    kerningLen := stbtt.GetKerningTableLength(&fontInfo)
    kerningData := make([]stbtt.kerningentry, kerningLen)
    kerningLen = stbtt.GetKerningTable(&fontInfo, raw_data(kerningData), kerningLen)

    for i in 0..<kerningLen {
        info := kerningData[i]
        key := KerningKey{
            rune1 = info.glyph1,
            rune2 = info.glyph2,
        }
        font.kerningTable[key] = f32(info.advance) * scaleFactor

        // fmt.println(info)
    }

    return
}



LoadFontFromFile :: proc(renderCtx: ^RenderContext, fileName: string, fontSize: int) -> (font: Font) {
    fontInfo: stbtt.fontinfo
    font.type = .Bitmap

    oversampleX :: 3
    oversampleY :: 1
    padding     :: 1

    fileData, ok := os.read_entire_file(fileName, context.temp_allocator)
    if ok == false {
        fmt.eprintf("Failed To Load File: %v !!\n", fileName)
        return
    }

    if stbtt.InitFont(&fontInfo, raw_data(fileData), 0) == false {
        fmt.eprintf("Failed To Init a Font: %v !!\n", fileName)
        return
    }

    scaleFactor := stbtt.ScaleForPixelHeight(&fontInfo, f32(fontSize))

    ascent, descent, lineGap: i32
    stbtt.GetFontVMetrics(&fontInfo, &ascent, &descent, &lineGap)

    font.ascent  = f32(ascent) * scaleFactor
    font.descent = f32(descent) * scaleFactor
    font.lineGap = f32(lineGap) * scaleFactor
    font.lineHeight = font.ascent - font.descent + font.lineGap

    surface: int
    for i in GLYPH_RANGE_LOW..<GLYPH_RANGE_HIGH {
        x0, y0, x1, y1 : i32

        stbtt.GetCodepointBitmapBoxSubpixel(
            &fontInfo, 
            rune(i),
            oversampleX * scaleFactor,
            oversampleY * scaleFactor,
            0, 0,
            &x0, &y0, &x1, &y1,
        )

        w := x1 - x0 + padding + oversampleX - 1
        h := y1 - y0 + padding + oversampleY - 1

        surface += int(w * h)
    }

    sqrSurface := int(math.sqrt(f32(surface)) + 1)
    bitmapSize := cast(i32) coreMath.next_power_of_two(sqrSurface)

    dataCount := bitmapSize * bitmapSize

    C :: struct {
        r, g, b, a : u8,
    }

    bitmap      := make([]u8, dataCount, context.temp_allocator)
    colorBitmap := make([]C, dataCount, context.temp_allocator)

    packContext: stbtt.pack_context
    packedChars: [GLYPH_COUNT]stbtt.packedchar

    stbtt.PackBegin(&packContext, raw_data(bitmap), bitmapSize, bitmapSize, 0, padding, nil)
    stbtt.PackSetOversampling(&packContext, oversampleX, oversampleY)
    stbtt.PackFontRange(&packContext, raw_data(fileData), 0, f32(fontSize), GLYPH_RANGE_LOW, GLYPH_COUNT, &(packedChars[0]))
    stbtt.PackEnd(&packContext)

    for i in 0..<dataCount {
        colorBitmap[i] = {
            r = 255,
            g = 255,
            b = 255,
            a = bitmap[i],
        }
    }

    font.size = fontSize

    for i in 0..<GLYPH_COUNT {
        m := packedChars[i]

        tempX, tempY: f32
        quad: stbtt.aligned_quad

        stbtt.GetPackedQuad(&(packedChars[0]), bitmapSize, bitmapSize,
                      i32(i), &tempX, &tempY, &quad, false);

        font.glyphData[i].codepoint = rune(i + GLYPH_RANGE_LOW)

        font.glyphData[i].atlasPos  = { quad.s0, quad.t0 }
        font.glyphData[i].atlasSize = { quad.s1 - quad.s0, 
                                        quad.t1 - quad.t0, }

        font.glyphData[i].pixelWidth  = int(quad.x1 - quad.x0)
        font.glyphData[i].pixelHeight = int(quad.y1 - quad.y0)

        font.glyphData[i].offset = { packedChars[i].xoff, packedChars[i].yoff }
        font.glyphData[i].advanceX = int(packedChars[i].xadvance)
    }

    font.atlas = CreateTexture(renderCtx, mem.slice_to_bytes(colorBitmap), int(bitmapSize), int(bitmapSize), 4, .Bilinear)

    kerningLen := stbtt.GetKerningTableLength(&fontInfo)
    kerningData := make([]stbtt.kerningentry, kerningLen)
    kerningLen = stbtt.GetKerningTable(&fontInfo, raw_data(kerningData), kerningLen)

    for i in 0..<kerningLen {
        info := kerningData[i]
        key := KerningKey{
            rune1 = info.glyph1,
            rune2 = info.glyph2,
        }
        font.kerningTable[key] = f32(info.advance) * scaleFactor

        // fmt.println(info)
    }

    return
}