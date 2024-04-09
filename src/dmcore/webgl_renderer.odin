//+build js
package dmcore

import gl "vendor:wasm/WebGL"

import "core:fmt"

ScreenSpaceRectShaderSource := #load("shaders/glsl/ScreenSpaceRect.glsl", string)
SpriteShaderSource := #load("shaders/glsl/Sprite.glsl", string)
SDFFontSource := #load("shaders/glsl/SDFFont.glsl", string)

PerFrameDataBindingPoint :: 0
perFrameDataBuffer: gl.Buffer

PerFrameData :: struct {
    MVP: mat4
}

////

InitRenderContext :: proc(ctx: ^RenderContext) {
    assert(ctx != nil)

    InitResourcePool(&ctx.textures, 128)
    InitResourcePool(&ctx.shaders, 16)

    ctx.DrawBatch = DrawBatch

    ctx.defaultShaders[.ScreenSpaceRect] = CompileShaderSource(ctx, ScreenSpaceRectShaderSource)
    ctx.defaultShaders[.Sprite] = CompileShaderSource(ctx, SpriteShaderSource)
    ctx.defaultShaders[.SDFFont] = CompileShaderSource(ctx, SDFFontSource)

    perFrameDataBuffer = gl.CreateBuffer()
    gl.BindBuffer(gl.UNIFORM_BUFFER, perFrameDataBuffer)
    gl.BufferData(gl.UNIFORM_BUFFER, size_of(PerFrameData), nil, gl.DYNAMIC_DRAW)
    gl.BindBufferRange(gl.UNIFORM_BUFFER, PerFrameDataBindingPoint,
                       perFrameDataBuffer, 0, size_of(PerFrameData))
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

    //////


    texData := []u8{255, 255, 255, 255}
    ctx.whiteTexture = CreateTexture(ctx, texData, 1, 1, 4, .Point)

    InitRectBatch(ctx, &ctx.defaultBatch, 2048)
    CreatePrimitiveBatch(ctx, 4086)

    ctx.frameSize = {800, 600}

    /////

    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

}

////////
MVP: mat4

FlushCommands :: proc(using ctx: ^RenderContext) {
    frameData: PerFrameData

    //@TODO: set proper viewport
    gl.Viewport(0, 0, 800, 600)

    for c in &commandBuffer.commands {
        switch cmd in &c {
        case ClearColorCommand:
            c := cmd.clearColor
            gl.ClearColor(c.r, c.g, c.b, c.a)
            gl.Clear(gl.COLOR_BUFFER_BIT)

        case CameraCommand:
            view := GetViewMatrix(cmd.camera)
            proj := GetProjectionMatrixNTO(cmd.camera)

            frameData.MVP = proj * view
            MVP = proj * view

            gl.BindBuffer(gl.UNIFORM_BUFFER, perFrameDataBuffer)
            gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(PerFrameData), &frameData)
            gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

        case DrawRectCommand:
            if ctx.defaultBatch.shader.gen != 0 && 
               ctx.defaultBatch.shader != cmd.shader {
                DrawBatch(ctx, &ctx.defaultBatch)
            }

            if ctx.defaultBatch.texture.gen != 0 && 
               ctx.defaultBatch.texture != cmd.texture {
                DrawBatch(ctx, &ctx.defaultBatch)
            }

            ctx.defaultBatch.shader = cmd.shader
            ctx.defaultBatch.texture = cmd.texture

            entry := RectBatchEntry {
                position = cmd.position,
                size = cmd.size,
                rotation = cmd.rotation,

                texPos  = {cmd.texSource.x, cmd.texSource.y},
                texSize = {cmd.texSource.width, cmd.texSource.height},
                pivot = cmd.pivot,
                color = cmd.tint,
            }

            AddBatchEntry(ctx, &ctx.defaultBatch, entry)
            case DrawMeshCommand:
        }

    }

    DrawBatch(ctx, &ctx.defaultBatch)

    clear(&commandBuffer.commands)
}

CreatePrimitiveBatch :: proc(ctx: ^RenderContext, maxCount: int) {
    // ctx.debugBatch.buffer = make([]PrimitiveVertex, maxCount)

    // TODO: finish
}
