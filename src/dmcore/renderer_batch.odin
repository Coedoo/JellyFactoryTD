package dmcore

import math "core:math/linalg/glsl"

import coreMath "core:math"

import "core:fmt"

///////////////////////////////
/// Rect rendering
//////////////////////////////

RectBatchEntry :: struct {
    position: v2,
    size:     v2,
    rotation: f32,

    texPos:   iv2,
    texSize:  iv2,

    pivot: v2,

    color: color,
}

RectBatch :: struct {
    count: int,
    maxCount: int,
    buffer: []RectBatchEntry,

    texture: TexHandle,
    shader:  ShaderHandle,

    backend: _RectBatch,
}

CreateRectBatch :: proc(renderCtx: ^RenderContext, count: int) -> (batch: RectBatch) {
    InitRectBatch(renderCtx, &batch, count)

    return batch
}

AddBatchEntry :: proc(ctx: ^RenderContext, batch: ^RectBatch, entry: RectBatchEntry) {
    assert(batch.buffer != nil)
    assert(batch.count < len(batch.buffer))

    batch.buffer[batch.count] = entry
    batch.count += 1
}

//////////////
// Debug drawing
/////////////

PrimitiveVertex :: struct {
    pos: v3,
    color: color,
}

PrimitiveBatch :: struct {
    shader: ShaderHandle,
    gpuBufferSize: int,
    buffer: [dynamic]PrimitiveVertex,
}


DrawDebugLine :: proc(ctx: ^RenderContext, a, b: v2, screenSpace: bool, color: color = RED) {
    batch := &ctx.debugBatch if screenSpace == false else &ctx.debugBatchScreen

    append(&batch.buffer, PrimitiveVertex{ToV3(a), color})
    append(&batch.buffer, PrimitiveVertex{ToV3(b), color})
}


DrawDebugBox :: proc(ctx: ^RenderContext, pos, size: v2, screenSpace: bool, color: color = GREEN) {
    batch := &ctx.debugBatch if screenSpace == false else &ctx.debugBatchScreen

    left  := pos.x - size.x / 2
    right := pos.x + size.x / 2
    top   := pos.y + size.y / 2
    bot   := pos.y - size.y / 2

    a := v3{left, bot, 0}
    b := v3{right, bot, 0}
    c := v3{right, top, 0}
    d := v3{left, top, 0}

    append(&batch.buffer, PrimitiveVertex{a, color})
    append(&batch.buffer, PrimitiveVertex{b, color})
    append(&batch.buffer, PrimitiveVertex{b, color})
    append(&batch.buffer, PrimitiveVertex{c, color})
    append(&batch.buffer, PrimitiveVertex{c, color})
    append(&batch.buffer, PrimitiveVertex{d, color})
    append(&batch.buffer, PrimitiveVertex{d, color})
    append(&batch.buffer, PrimitiveVertex{a, color})

}

DrawDebugBounds :: proc(ctx: ^RenderContext, bounds: Bounds2D, screenSpace: bool, color := GREEN) {
    pos := v2{
        bounds.left + (bounds.right - bounds.left) / 2,
        bounds.bot  + (bounds.top - bounds.bot) / 2,
    }

    size := v2{
        (bounds.right - bounds.left),
        (bounds.top - bounds.bot),
    }

    DrawDebugBox(ctx, pos, size, screenSpace, color)
}

DrawDebugCircle :: proc(ctx: ^RenderContext, pos: v2, radius: f32, screenSpace: bool, color: color = GREEN) {
    batch := &ctx.debugBatch if screenSpace == false else &ctx.debugBatchScreen

    resolution :: 32

    GetPosition :: proc(i: int, pos: v2, radius: f32) -> v3 {
        angle := f32(i) / f32(resolution) * coreMath.PI * 2
        pos := v3{
            coreMath.cos(angle),
            coreMath.sin(angle),
            0
        } * radius + {pos.x, pos.y, 0}

        return pos
    }

    append(&batch.buffer, PrimitiveVertex{ToV3(pos), color})
    append(&batch.buffer, PrimitiveVertex{GetPosition(0, pos, radius), color})

    for i in 0..<resolution {
        posA := GetPosition(i, pos, radius)
        posB := GetPosition(i + 1, pos, radius)

        append(&batch.buffer, PrimitiveVertex{posA, color})
        append(&batch.buffer, PrimitiveVertex{posB, color})
    }
}

DrawDebugRay :: proc(ctx: ^RenderContext, ray: Ray2D, screenSpace: bool, distance: f32 = 1., color := GREEN) {
    dir := math.normalize(ray.direction) * distance
    DrawDebugLine(ctx, ray.origin, ray.origin + dir, screenSpace, color)
}