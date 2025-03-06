#+build js
package dmcore

import gl "vendor:wasm/WebGL"

import "core:fmt"

_RectBatch :: struct {
    buffer: gl.Buffer,
    vao: gl.VertexArrayObject,
}

InitRectBatch :: proc(renderCtx: ^RenderContext, batch: ^RectBatch, count: int) {

    batch.backend.vao = gl.CreateVertexArray()
    gl.BindVertexArray(batch.backend.vao)

    batch.backend.buffer = gl.CreateBuffer()
    gl.BindBuffer(gl.ARRAY_BUFFER, batch.backend.buffer)
    gl.BufferData(gl.ARRAY_BUFFER, count * size_of(RectBatchEntry), nil, gl.DYNAMIC_DRAW)

    // layout (location = 0) in vec2 aPos;
    // layout (location = 1) in vec2 aSize;
    // layout (location = 2) in vec2 aTexPos;
    // layout (location = 3) in vec2 aTexSize;
    // layout (location = 4) in vec4 aColor;

    gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of(RectBatchEntry), offset_of(RectBatchEntry, position))
    gl.VertexAttribPointer(1, 2, gl.FLOAT, false, size_of(RectBatchEntry), offset_of(RectBatchEntry, size))
    gl.VertexAttribPointer(2, 2, gl.UNSIGNED_INT,   false, size_of(RectBatchEntry), offset_of(RectBatchEntry, texPos))
    gl.VertexAttribPointer(3, 2, gl.UNSIGNED_INT,   false, size_of(RectBatchEntry), offset_of(RectBatchEntry, texSize))
    gl.VertexAttribPointer(4, 4, gl.FLOAT, false, size_of(RectBatchEntry), offset_of(RectBatchEntry, color))

    // @TODO: split input layour between SSRect and SpriteRect
    gl.VertexAttribPointer(5, 1, gl.FLOAT, false, size_of(RectBatchEntry), offset_of(RectBatchEntry, rotation))
    gl.VertexAttribPointer(6, 2, gl.FLOAT, false, size_of(RectBatchEntry), offset_of(RectBatchEntry, pivot))


    gl.VertexAttribDivisor(0, 1)
    gl.VertexAttribDivisor(1, 1)
    gl.VertexAttribDivisor(2, 1)
    gl.VertexAttribDivisor(3, 1)
    gl.VertexAttribDivisor(4, 1)
    gl.VertexAttribDivisor(5, 1)
    gl.VertexAttribDivisor(6, 1)

    gl.EnableVertexAttribArray(0)
    gl.EnableVertexAttribArray(1)
    gl.EnableVertexAttribArray(2)
    gl.EnableVertexAttribArray(3)
    gl.EnableVertexAttribArray(4)
    gl.EnableVertexAttribArray(5)
    gl.EnableVertexAttribArray(6)

    gl.BindVertexArray(0)
    gl.BindBuffer(gl.ARRAY_BUFFER, 0)

    batch.buffer = make([]RectBatchEntry, count)
    batch.maxCount = count
}

DrawBatch :: proc(ctx: ^RenderContext, batch: ^RectBatch) {
    if(batch.count == 0) {
        return
    }

    tex, ok := GetElementPtr(ctx.textures, batch.texture)
    gl.BindTexture(gl.TEXTURE_2D, tex.texId)

    shader := GetElement(ctx.shaders, batch.shader)
    gl.UseProgram(shader.backend.shaderID)

    blockIdx := gl.GetUniformBlockIndex(shader.backend.shaderID, "PerFrameData")
    if blockIdx != -1 {
        gl.UniformBlockBinding(shader.backend.shaderID, blockIdx, PerFrameDataBindingPoint)
    }
    // gl.UniformMatrix4fv(gl.GetUniformLocation(shader.shaderID, "MVP"), MVP)
    
    oneOverAtlasSize := v2{1 / f32(tex.width), 1 / f32(tex.height)}
    // @TODO: get frame size from context
    screenSize := v2{ 2 / f32(ctx.frameSize.x), -2 / f32(ctx.frameSize.y)}

    gl.Uniform2fv(gl.GetUniformLocation(shader.backend.shaderID, "OneOverAtlasSize"), oneOverAtlasSize)
    gl.Uniform2fv(gl.GetUniformLocation(shader.backend.shaderID, "ScreenSize"), screenSize)

    gl.BindVertexArray(batch.backend.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, batch.backend.buffer)


    gl.BufferSubData(gl.ARRAY_BUFFER, 0, batch.count * size_of(RectBatchEntry), raw_data(batch.buffer))

    // fmt.println(mem.slice_data_cast([]u32, batch.buffer[0:1]))

    gl.VertexAttribDivisor(0, 1)
    gl.VertexAttribDivisor(1, 1)
    gl.VertexAttribDivisor(2, 1)
    gl.VertexAttribDivisor(3, 1)
    gl.VertexAttribDivisor(4, 1)
    gl.VertexAttribDivisor(5, 1)
    gl.VertexAttribDivisor(6, 1)

    gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, batch.count)

    gl.BindVertexArray(0)
    gl.BindTexture(gl.TEXTURE_2D, 0)
    gl.UseProgram(0)
    gl.BindBuffer(gl.ARRAY_BUFFER, 0)

    batch.count = 0
}


CreatePrimitiveBatch :: proc(ctx: ^RenderContext, maxCount: int, shaderSource: string) -> (ret: PrimitiveBatch) {
    return {}
}

DrawPrimitiveBatch :: proc(batch: ^PrimitiveBatch, ctx: ^RenderContext) {
}
