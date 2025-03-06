#+build windows
package dmcore

// import stbtt "vendor:stb/truetype"
// import stbrp "vendor:stb/rect_pack"

// import "core:mem"
// import "core:os"
// import "core:fmt"

// import math "core:math/linalg/glsl"
// import coreMath "core:math"

// LoadFontSDF :: proc(renderCtx: ^RenderContext, data: []u8, fontSize: int) -> FontHandle {
//     // fileData, ok := os.read_entire_file(fileName, context.temp_allocator)
//     // if ok == false {
//     //     fmt.eprintf("Failed To Load File: %v !!\n", fileName)
//     //     return {}
//     // }

//     font: Font
//     bitmap, bitmapSize := InitFontSDF(&font, data, fontSize)

//     font.atlas = CreateTexture(renderCtx, mem.slice_to_bytes(bitmap), int(bitmapSize), int(bitmapSize), 4, .Bilinear)

//     handle := AppendElement(&renderCtx.fonts, font)
//     return handle
// }

// InitFontSDF :: proc(font: ^Font, data: []u8, fontSize: int) -> (bitmap: []i32, bitmapSize: i32) {
//     padding :: 3
//     onEdgeValue :: 128
//     distanceScale :: 32

//     // fileData, ok := os.read_entire_file(fileName, context.temp_allocator)
//     // if ok == false {
//     //     fmt.eprintf("Failed To Load File: %v !!\n", fileName)
//     //     return
//     // }

//     fontInfo: stbtt.fontinfo
//     if stbtt.InitFont(&fontInfo, raw_data(data), 0) == false {
//         // @TODO: add name to font for easier recognition
//         fmt.eprintf("Failed To Init a Font: %v !!\n")
//         return
//     }

//     font.size = fontSize
//     font.type = .SDF

//     scaleFactor := stbtt.ScaleForPixelHeight(&fontInfo, f32(fontSize))

//     ascent, descent, lineGap: i32
//     stbtt.GetFontVMetrics(&fontInfo, &ascent, &descent, &lineGap)

//     font.ascent  = f32(ascent) * scaleFactor
//     font.descent = f32(descent) * scaleFactor
//     font.lineGap = f32(lineGap) * scaleFactor
//     font.lineHeight = font.ascent - font.descent + font.lineGap


//     bitmaps: [GLYPH_COUNT][^]byte
//     defer for b in bitmaps {
//         stbtt.FreeSDF(b, nil)
//     }

//     area: i32
//     for i in GLYPH_RANGE_LOW..<GLYPH_RANGE_HIGH {
//         width, height: i32
//         xoff, yoff: i32

//         bitmaps[i - GLYPH_RANGE_LOW] = stbtt.GetCodepointSDF(
//                                                 &fontInfo, 
//                                                 scaleFactor, 
//                                                 i32(i), 
//                                                 padding, 
//                                                 onEdgeValue, 
//                                                 distanceScale, 
//                                                 &width, 
//                                                 &height, 
//                                                 &xoff, 
//                                                 &yoff
//                                             )

//         advanceX: i32
//         stbtt.GetCodepointHMetrics(&fontInfo, rune(i), &advanceX, nil)

//         glyph := GlyphData {
//             codepoint = rune(i),
//             pixelWidth  = int(width),
//             pixelHeight = int(height),

//             offset = {f32(xoff), f32(yoff)},
//             advanceX = int(f32(advanceX) * scaleFactor),
//         }

//         fmt.println(glyph.codepoint, glyph.offset)

//         idx := GetCodepointIndex(rune(i))
//         font.glyphData[idx] = glyph

//         area += width * height
//     }

//     sqrSurface := int(math.sqrt(f32(area)) + 1)
//     bitmapSize = cast(i32) coreMath.next_power_of_two(sqrSurface)

//     rpCtx := new(stbrp.Context, context.temp_allocator)
//     nodes := make([]stbrp.Node, GLYPH_COUNT, context.temp_allocator)
//     rects := make([]stbrp.Rect, GLYPH_COUNT, context.temp_allocator)

//     stbrp.init_target(rpCtx, bitmapSize, bitmapSize, raw_data(nodes), i32(len(nodes)))

//     for g, i in font.glyphData {
//         rects[i].id = i32(g.codepoint)
//         rects[i].w = cast(stbrp.Coord) g.pixelWidth
//         rects[i].h = cast(stbrp.Coord) g.pixelHeight
//     }

//     stbrp.pack_rects(rpCtx, raw_data(rects), i32(len(rects)))

//     bitmap = make([]i32, bitmapSize * bitmapSize, context.temp_allocator)
//     for r, i in rects {
//         if r.was_packed == false {
//             fmt.eprintln("Failed To pack codepoint:", rune(r.id), "(", r.id, ")")
//             continue
//         }

//         if bitmaps[i] == nil {
//             continue
//         }

//         x := i32(r.x)
//         y := i32(r.y)
//         w := i32(font.glyphData[i].pixelWidth)
//         h := i32(font.glyphData[i].pixelHeight)

//         for bitmapX in 0..<w {
//             for bitmapY in 0..<h {
//                 atlasX := x + bitmapX
//                 atlasY := y + bitmapY

//                 bitmapIdx := bitmapY * w + bitmapX
//                 atlasIdx := atlasY * bitmapSize + atlasX

//                 b := bitmaps[i]
//                 v := b[bitmapIdx]

//                 bitmap[atlasIdx] = transmute(i32) [4]u8{255, 255, 255, v}
//             }
//         }

//         font.glyphData[i].atlasPos = {f32(r.x) / f32(bitmapSize), f32(r.y) / f32(bitmapSize)}
//         font.glyphData[i].atlasSize = {f32(w) / f32(bitmapSize), f32(h) / f32(bitmapSize)}
//     }

//     kerningLen := stbtt.GetKerningTableLength(&fontInfo)
//     kerningData := make([]stbtt.kerningentry, kerningLen)
//     kerningLen = stbtt.GetKerningTable(&fontInfo, raw_data(kerningData), kerningLen)

//     for i in 0..<kerningLen {
//         info := kerningData[i]
//         key := KerningKey{
//             rune1 = info.glyph1,
//             rune2 = info.glyph2,
//         }
//         font.kerningTable[key] = f32(info.advance) * scaleFactor

//         // fmt.println(info)
//     }

//     return
// }



// LoadFontFromFile :: proc(renderCtx: ^RenderContext, fileName: string, fontSize: int) -> (font: Font) {
//     fontInfo: stbtt.fontinfo
//     font.type = .Bitmap

//     oversampleX :: 3
//     oversampleY :: 1
//     padding     :: 1

//     fileData, ok := os.read_entire_file(fileName, context.temp_allocator)
//     if ok == false {
//         fmt.eprintf("Failed To Load File: %v !!\n", fileName)
//         return
//     }

//     if stbtt.InitFont(&fontInfo, raw_data(fileData), 0) == false {
//         fmt.eprintf("Failed To Init a Font: %v !!\n", fileName)
//         return
//     }

//     scaleFactor := stbtt.ScaleForPixelHeight(&fontInfo, f32(fontSize))

//     ascent, descent, lineGap: i32
//     stbtt.GetFontVMetrics(&fontInfo, &ascent, &descent, &lineGap)

//     font.ascent  = f32(ascent) * scaleFactor
//     font.descent = f32(descent) * scaleFactor
//     font.lineGap = f32(lineGap) * scaleFactor
//     font.lineHeight = font.ascent - font.descent + font.lineGap

//     surface: int
//     for i in GLYPH_RANGE_LOW..<GLYPH_RANGE_HIGH {
//         x0, y0, x1, y1 : i32

//         stbtt.GetCodepointBitmapBoxSubpixel(
//             &fontInfo, 
//             rune(i),
//             oversampleX * scaleFactor,
//             oversampleY * scaleFactor,
//             0, 0,
//             &x0, &y0, &x1, &y1,
//         )

//         w := x1 - x0 + padding + oversampleX - 1
//         h := y1 - y0 + padding + oversampleY - 1

//         surface += int(w * h)
//     }

//     sqrSurface := int(math.sqrt(f32(surface)) + 1)
//     bitmapSize := cast(i32) coreMath.next_power_of_two(sqrSurface)

//     dataCount := bitmapSize * bitmapSize

//     C :: struct {
//         r, g, b, a : u8,
//     }

//     bitmap      := make([]u8, dataCount, context.temp_allocator)
//     colorBitmap := make([]C, dataCount, context.temp_allocator)

//     packContext: stbtt.pack_context
//     packedChars: [GLYPH_COUNT]stbtt.packedchar

//     stbtt.PackBegin(&packContext, raw_data(bitmap), bitmapSize, bitmapSize, 0, padding, nil)
//     stbtt.PackSetOversampling(&packContext, oversampleX, oversampleY)
//     stbtt.PackFontRange(&packContext, raw_data(fileData), 0, f32(fontSize), GLYPH_RANGE_LOW, GLYPH_COUNT, &(packedChars[0]))
//     stbtt.PackEnd(&packContext)

//     for i in 0..<dataCount {
//         colorBitmap[i] = {
//             r = 255,
//             g = 255,
//             b = 255,
//             a = bitmap[i],
//         }
//     }

//     font.size = fontSize

//     for i in 0..<GLYPH_COUNT {
//         m := packedChars[i]

//         tempX, tempY: f32
//         quad: stbtt.aligned_quad

//         stbtt.GetPackedQuad(&(packedChars[0]), bitmapSize, bitmapSize,
//                       i32(i), &tempX, &tempY, &quad, false);

//         font.glyphData[i].codepoint = rune(i + GLYPH_RANGE_LOW)

//         font.glyphData[i].atlasPos  = { quad.s0, quad.t0 }
//         font.glyphData[i].atlasSize = { quad.s1 - quad.s0, 
//                                         quad.t1 - quad.t0, }

//         font.glyphData[i].pixelWidth  = int(quad.x1 - quad.x0)
//         font.glyphData[i].pixelHeight = int(quad.y1 - quad.y0)

//         font.glyphData[i].offset = { packedChars[i].xoff, packedChars[i].yoff }
//         font.glyphData[i].advanceX = int(packedChars[i].xadvance)
//     }

//     font.atlas = CreateTexture(renderCtx, mem.slice_to_bytes(colorBitmap), int(bitmapSize), int(bitmapSize), 4, .Bilinear)

//     kerningLen := stbtt.GetKerningTableLength(&fontInfo)
//     kerningData := make([]stbtt.kerningentry, kerningLen)
//     kerningLen = stbtt.GetKerningTable(&fontInfo, raw_data(kerningData), kerningLen)

//     for i in 0..<kerningLen {
//         info := kerningData[i]
//         key := KerningKey{
//             rune1 = info.glyph1,
//             rune2 = info.glyph2,
//         }
//         font.kerningTable[key] = f32(info.advance) * scaleFactor

//         // fmt.println(info)
//     }

//     return
// }