#+build js
package dmcore

import gl "vendor:wasm/WebGL"
import sa "core:container/small_array"

import "core:math/linalg/glsl"

import "core:fmt"

ScreenSpaceRectShaderSource := #load("shaders/glsl/ScreenSpaceRect.glsl", string)
SpriteShaderSource := #load("shaders/glsl/Sprite.glsl", string)
SDFFontSource := #load("shaders/glsl/SDFFont.glsl", string)
GridShaderSource := #load("shaders/glsl/Grid.glsl", string)


PerFrameDataBindingPoint :: 0

RenderContextBackend :: struct {
    perFrameDataBuffer: gl.Buffer
}

CreateRenderContextBackend :: proc() -> ^RenderContext {
    ctx := new(RenderContext)

    ctx.perFrameDataBuffer = gl.CreateBuffer()
    gl.BindBuffer(gl.UNIFORM_BUFFER, ctx.perFrameDataBuffer)
    gl.BufferData(gl.UNIFORM_BUFFER, size_of(PerFrameData), nil, gl.DYNAMIC_DRAW)
    gl.BindBufferRange(gl.UNIFORM_BUFFER, PerFrameDataBindingPoint,
                       ctx.perFrameDataBuffer, 0, size_of(PerFrameData))
    gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, ctx.perFrameDataBuffer)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)


    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    return ctx
}

////////
MVP: mat4

FlushCommands :: proc(ctx: ^RenderContext) {
    gl.Viewport(0, 0, ctx.frameSize.x, ctx.frameSize.y)

    // Default camera
    view := GetViewMatrix(ctx.camera)
    proj := GetProjectionMatrixNTO(ctx.camera)
    frameData: PerFrameData
    frameData.VPMat = proj * view
    frameData.invVPMat = glsl.inverse(frameData.VPMat)

    gl.BindBuffer(gl.UNIFORM_BUFFER, ctx.perFrameDataBuffer)
    gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(PerFrameData), &frameData)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

    shadersStack: sa.Small_Array(128, ShaderHandle)

    for c in &ctx.commandBuffer.commands {
        switch cmd in c {
        case ClearColorCommand:
            c := cmd.clearColor
            gl.ClearColor(c.r, c.g, c.b, c.a)
            gl.Clear(gl.COLOR_BUFFER_BIT)

        case CameraCommand:
            view := GetViewMatrix(cmd.camera)
            proj := GetProjectionMatrixNTO(cmd.camera)

            frameData.VPMat = proj * view
            frameData.invVPMat = glsl.inverse(frameData.VPMat)

            gl.BindBuffer(gl.UNIFORM_BUFFER, ctx.perFrameDataBuffer)
            gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(PerFrameData), &frameData)
            gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

        case DrawRectCommand:
            if ctx.defaultBatch.count >= ctx.defaultBatch.maxCount {
                DrawBatch(ctx, &ctx.defaultBatch)
            }

            shadersLen := sa.len(shadersStack)
            shader :=  shadersLen > 0 ? sa.get(shadersStack, shadersLen - 1) : cmd.shader

            if ctx.defaultBatch.shader.gen != 0 && 
               ctx.defaultBatch.shader != shader {
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

        case DrawGridCommand:

        case DrawMeshCommand:


        case PushShaderCommand: sa.push(&shadersStack, cmd.shader)
        case PopShaderCommand:  sa.pop_back(&shadersStack)

        }

    }

    DrawBatch(ctx, &ctx.defaultBatch)

    clear(&ctx.commandBuffer.commands)
}