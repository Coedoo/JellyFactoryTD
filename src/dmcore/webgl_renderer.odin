#+build js
package dmcore

import gl "vendor:wasm/WebGL"
import sa "core:container/small_array"

import "core:math/linalg/glsl"

import "core:fmt"

BlitShaderSource := #load("shaders/glsl/Blit.glsl", string)
RectShaderSource := #load("shaders/glsl/Rect.glsl", string)
SpriteShaderSource := #load("shaders/glsl/Sprite.glsl", string)
SDFFontSource := #load("shaders/glsl/SDFFont.glsl", string)
GridShaderSource := #load("shaders/glsl/Grid.glsl", string)


PerFrameDataBindingPoint :: 0

RenderContextBackend :: struct {
    perFrameDataBuffer: gl.Buffer,
    ppGlobalUniformBuffer: gl.Buffer,
}

CreateRenderContextBackend :: proc() -> ^RenderContext {
    ctx := new(RenderContext)

    // global frame uniforms
    ctx.perFrameDataBuffer = gl.CreateBuffer()
    gl.BindBuffer(gl.UNIFORM_BUFFER, ctx.perFrameDataBuffer)
    gl.BufferData(gl.UNIFORM_BUFFER, size_of(PerFrameData), nil, gl.DYNAMIC_DRAW)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

    // pp global uniforms
    ctx.ppGlobalUniformBuffer = gl.CreateBuffer()
    gl.BindBuffer(gl.UNIFORM_BUFFER, ctx.ppGlobalUniformBuffer)
    gl.BufferData(gl.UNIFORM_BUFFER, size_of(PostProcessGlobalData), nil, gl.DYNAMIC_DRAW)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)


    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    return ctx
}


StartFrame :: proc(ctx: ^RenderContext) {
    SetCamera(ctx.camera)

    gl.Viewport(0, 0, ctx.frameSize.x, ctx.frameSize.y)

    renderTarget := GetElement(ctx.framebuffers, ctx.ppFramebufferSrc)
    gl.BindFramebuffer(gl.FRAMEBUFFER, renderTarget.glFramebuffer)
}

EndFrame :: proc(ctx: ^RenderContext) {
    DrawBatch(ctx, &ctx.defaultBatch)

    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

    shader := GetElement(ctx.shaders, ctx.defaultShaders[.Blit])
    gl.UseProgram(shader.shaderID)

    ppSrc := GetElement(ctx.framebuffers, ctx.ppFramebufferSrc)
    gl.BindTexture(gl.TEXTURE_2D, ppSrc.textureAttachment)
    gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)
}

ClearColor :: proc(color: color) {
    gl.ClearColor(color.r, color.g, color.b, color.a)
    gl.Clear(cast(u32) gl.COLOR_BUFFER_BIT)
}

SetCamera :: proc(camera: Camera) {
    view := GetViewMatrix(camera)
    proj := GetProjectionMatrixNTO(camera)

    frameData: PerFrameData
    frameData.VPMat = proj * view
    frameData.invVPMat = glsl.inverse(frameData.VPMat)
    frameData.screenSpace = 0

    gl.BindBuffer(gl.UNIFORM_BUFFER, renderCtx.perFrameDataBuffer)
    gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(PerFrameData), &frameData)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

    gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, renderCtx.perFrameDataBuffer)
}

DrawMesh :: proc(mesh: ^Mesh, pos: v2, shader: ShaderHandle) {

}

DrawGrid :: proc() {
    // @TODO
}

BeginScreenSpace :: proc() {
    DrawBatch(renderCtx, &renderCtx.defaultBatch)

    renderCtx.inScreenSpace = true

    scale := [3]f32{ 2.0 / f32(renderCtx.frameSize.x), -2.0 / f32(renderCtx.frameSize.y), 0}
    mat := glsl.mat4Translate({-1, 1, 0}) * glsl.mat4Scale(scale)

    frameData: PerFrameData
    frameData.VPMat = mat
    frameData.invVPMat = glsl.inverse(mat)
    frameData.screenSpace = 1

    gl.BindBuffer(gl.UNIFORM_BUFFER, renderCtx.perFrameDataBuffer)
    gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(PerFrameData), &frameData)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

    gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, renderCtx.perFrameDataBuffer)
}

EndScreenSpace :: proc() {
    DrawBatch(renderCtx, &renderCtx.defaultBatch)

    // TODO: cameras stack or something
    SetCamera(renderCtx.camera)
    renderCtx.inScreenSpace = false
}

UpdateBufferContent :: proc(buffer: GPUBufferHandle) {
    buff, ok := GetElementPtr(renderCtx.buffers, buffer)
    if ok {
        BackendUpdateBufferData(buff)
    }
}

BindBuffer :: proc(buffer: GPUBufferHandle, slot: int) {
    buff, ok := GetElementPtr(renderCtx.buffers, buffer)
    if ok {
        gl.BindBuffer(gl.UNIFORM_BUFFER, buff.glBuffer)
        gl.BufferSubData(gl.UNIFORM_BUFFER, 0, buff.dataLen, buff.dataPtr)
        gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

        gl.BindBufferBase(gl.UNIFORM_BUFFER, i32(slot), buff.glBuffer)
    }
}

BindFramebufferAsTexture :: proc(framebuffer: FramebufferHandle, slot: int) {
    fb := GetElement(renderCtx.framebuffers, framebuffer)
    gl.BindTexture(gl.TEXTURE_2D, fb.textureAttachment)
}

BindRenderTarget :: proc(framebuffer: FramebufferHandle) {
    panic("unfinished")
}

BeginPP :: proc() {
    DrawBatch(renderCtx, &renderCtx.defaultBatch)

    data := PostProcessGlobalData {
        resolution = renderCtx.frameSize,
        time = cast(f32) time.gameTime
    }

    gl.BindBuffer(gl.UNIFORM_BUFFER, renderCtx.ppGlobalUniformBuffer)
    gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(PostProcessGlobalData), &data)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

    gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, renderCtx.ppGlobalUniformBuffer)
}

DrawPP :: proc(pp: PostProcess) {
    shader := GetElement(renderCtx.shaders, pp.shader)
    if shader.shaderID == 0 {
        // TODO: I'm not sure if 0 is a correct value
        return
    }

    srcFB := GetElement(renderCtx.framebuffers, renderCtx.ppFramebufferSrc)
    destFB := GetElement(renderCtx.framebuffers, renderCtx.ppFramebufferDest)

    gl.BindFramebuffer(gl.FRAMEBUFFER, destFB.glFramebuffer)

    gl.UseProgram(shader.shaderID)
    gl.BindTexture(gl.TEXTURE_2D, srcFB.textureAttachment)

    blockIdx := gl.GetUniformBlockIndex(shader.shaderID, "globalUniforms")
    if blockIdx != -1 {
        gl.UniformBlockBinding(shader.shaderID, blockIdx, 0)
    }

    blockIdx = gl.GetUniformBlockIndex(shader.shaderID, "uniforms")
    if blockIdx != -1 {
        gl.UniformBlockBinding(shader.shaderID, blockIdx, 1)
    }

    gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

    // Swap buffers for next pass, if there is one
    renderCtx.ppFramebufferSrc, renderCtx.ppFramebufferDest = renderCtx.ppFramebufferDest, renderCtx.ppFramebufferSrc
}

FinishPP :: proc() {
    srcFB := GetElement(renderCtx.framebuffers, renderCtx.ppFramebufferSrc)
    gl.BindFramebuffer(gl.FRAMEBUFFER, srcFB.glFramebuffer)
}

////////
// MVP: mat4

// FlushCommands :: proc(ctx: ^RenderContext) {
//     gl.Viewport(0, 0, ctx.frameSize.x, ctx.frameSize.y)

//     renderTarget := GetElement(ctx.framebuffers, ctx.ppFramebufferSrc)
//     gl.BindFramebuffer(gl.FRAMEBUFFER, renderTarget.glFramebuffer)

//     // Default camera
//     view := GetViewMatrix(ctx.camera)
//     proj := GetProjectionMatrixNTO(ctx.camera)
//     frameData: PerFrameData
//     frameData.VPMat = proj * view
//     frameData.invVPMat = glsl.inverse(frameData.VPMat)
//     frameData.screenSpace = 0

//     gl.BindBuffer(gl.UNIFORM_BUFFER, ctx.perFrameDataBuffer)
//     gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(PerFrameData), &frameData)
//     gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

//     gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, ctx.perFrameDataBuffer)

//     shadersStack: sa.Small_Array(128, ShaderHandle)

//     for c in &ctx.commandBuffer.commands {
//         switch cmd in c {
//         case ClearColorCommand:
//             c := cmd.clearColor
//             gl.ClearColor(c.r, c.g, c.b, c.a)
//             gl.Clear(gl.COLOR_BUFFER_BIT)

//         case CameraCommand:
//             view = GetViewMatrix(cmd.camera)
//             proj = GetProjectionMatrixNTO(cmd.camera)

//             frameData.VPMat = proj * view
//             frameData.invVPMat = glsl.inverse(frameData.VPMat)
//             frameData.screenSpace = 0

//             gl.BindBuffer(gl.UNIFORM_BUFFER, ctx.perFrameDataBuffer)
//             gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(PerFrameData), &frameData)
//             gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

//             gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, ctx.perFrameDataBuffer)


//         case DrawRectCommand:
//             if ctx.defaultBatch.count >= ctx.defaultBatch.maxCount {
//                 DrawBatch(ctx, &ctx.defaultBatch)
//             }

//             shadersLen := sa.len(shadersStack)
//             shader :=  shadersLen > 0 ? sa.get(shadersStack, shadersLen - 1) : cmd.shader

//             if ctx.defaultBatch.shader.gen != 0 && 
//                ctx.defaultBatch.shader != shader {
//                 DrawBatch(ctx, &ctx.defaultBatch)
//             }

//             if ctx.defaultBatch.texture.gen != 0 && 
//                ctx.defaultBatch.texture != cmd.texture {
//                 DrawBatch(ctx, &ctx.defaultBatch)
//             }

//             ctx.defaultBatch.shader = cmd.shader
//             ctx.defaultBatch.texture = cmd.texture

//             entry := RectBatchEntry {
//                 position = cmd.position,
//                 size = cmd.size,
//                 rotation = cmd.rotation,

//                 texPos  = {cmd.texSource.x, cmd.texSource.y},
//                 texSize = {cmd.texSource.width, cmd.texSource.height},
//                 pivot = cmd.pivot,
//                 color = cmd.tint,
//             }

//             AddBatchEntry(ctx, &ctx.defaultBatch, entry)

//         case DrawGridCommand:

//         case DrawMeshCommand:


//         case PushShaderCommand: sa.push(&shadersStack, cmd.shader)
//         case PopShaderCommand:  sa.pop_back(&shadersStack)
//         case BeginScreenSpaceCommand:
//             DrawBatch(ctx, &ctx.defaultBatch)

//             scale := [3]f32{ 2.0 / f32(ctx.frameSize.x), -2.0 / f32(ctx.frameSize.y), 0}
//             mat := glsl.mat4Translate({-1, 1, 0}) * glsl.mat4Scale(scale)

//             frameData.VPMat = mat
//             frameData.invVPMat = glsl.inverse(mat)
//             frameData.screenSpace = 1

//             gl.BindBuffer(gl.UNIFORM_BUFFER, ctx.perFrameDataBuffer)
//             gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(PerFrameData), &frameData)
//             gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

//             gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, ctx.perFrameDataBuffer)

//         case EndScreenSpaceCommand:
//             DrawBatch(ctx, &ctx.defaultBatch)

//         case BindFBAsTextureCommand:
//             fb := GetElement(ctx.framebuffers, cmd.framebuffer)
//             gl.BindTexture(gl.TEXTURE_2D, fb.textureAttachment)

//         case BindRenderTargetCommand:
//             panic("unfinished")

//         case UpdateBufferContentCommand:
//             buff, ok := GetElementPtr(ctx.buffers, cmd.buffer)
//             if ok {
//                 BackendUpdateBufferData(buff)
//             }

//         case BindBufferCommand:
//             buff, ok := GetElementPtr(ctx.buffers, cmd.buffer)
//             if ok {
//                 gl.BindBuffer(gl.UNIFORM_BUFFER, buff.glBuffer)
//                 gl.BufferSubData(gl.UNIFORM_BUFFER, 0, buff.dataLen, buff.dataPtr)
//                 gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

//                 gl.BindBufferBase(gl.UNIFORM_BUFFER, i32(cmd.slot), buff.glBuffer)
//             }

//         case BeginPPCommand:
//             DrawBatch(ctx, &ctx.defaultBatch)

//             data := PostProcessGlobalData {
//                 resolution = ctx.frameSize,
//                 time = cast(f32) time.gameTime
//             }

//             gl.BindBuffer(gl.UNIFORM_BUFFER, ctx.ppGlobalUniformBuffer)
//             gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(PostProcessGlobalData), &data)
//             gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

//             gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, ctx.ppGlobalUniformBuffer)

//         case DrawPPCommand:
//             shader := GetElement(ctx.shaders, cmd.shader)
//             if shader.shaderID == 0 {
//                 // TODO: I'm not sure if 0 is a correct value
//                 continue
//             }

//             srcFB := GetElement(ctx.framebuffers, ctx.ppFramebufferSrc)
//             destFB := GetElement(ctx.framebuffers, ctx.ppFramebufferDest)

//             gl.BindFramebuffer(gl.FRAMEBUFFER, destFB.glFramebuffer)

//             gl.UseProgram(shader.shaderID)
//             gl.BindTexture(gl.TEXTURE_2D, srcFB.textureAttachment)

//             blockIdx := gl.GetUniformBlockIndex(shader.shaderID, "globalUniforms")
//             if blockIdx != -1 {
//                 gl.UniformBlockBinding(shader.shaderID, blockIdx, 0)
//             }

//             blockIdx = gl.GetUniformBlockIndex(shader.shaderID, "uniforms")
//             if blockIdx != -1 {
//                 gl.UniformBlockBinding(shader.shaderID, blockIdx, 1)
//             }

//             gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

//             // Swap buffers for next pass, if there is one
//             ctx.ppFramebufferSrc, ctx.ppFramebufferDest = ctx.ppFramebufferDest, ctx.ppFramebufferSrc

//         case FinishPPCommand:
//             srcFB := GetElement(ctx.framebuffers, ctx.ppFramebufferSrc)
//             gl.BindFramebuffer(gl.FRAMEBUFFER, srcFB.glFramebuffer)

//         }
//     }

//     DrawBatch(ctx, &ctx.defaultBatch)
//     clear(&ctx.commandBuffer.commands)

//     gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

//     shader := GetElement(ctx.shaders, ctx.defaultShaders[.Blit])
//     gl.UseProgram(shader.shaderID)

//     ppSrc := GetElement(ctx.framebuffers, ctx.ppFramebufferSrc)
//     gl.BindTexture(gl.TEXTURE_2D, ppSrc.textureAttachment)

//     gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)
// }