package dmcore

// SHADER
DefaultShaderType :: enum {
    Blit,
    Sprite,
    Rect,
    SDFFont,
    Grid,
}

Shader :: struct {
    handle: ShaderHandle,
    name: string,
    using backend: _Shader,
}


// FRAME BUFFER

FramebufferHandle :: Handle
Framebuffer :: struct {
    handle: FramebufferHandle,

    width, height: int,

    using backend: FramebufferBackend,
}

CreateFramebuffer :: proc (ctx: ^RenderContext, width := 0, height := 0) -> FramebufferHandle {
    fb := CreateElement(&ctx.framebuffers)

    fb.width  = width  if width  != 0 else int(ctx.frameSize.x)
    fb.height = height if height != 0 else int(ctx.frameSize.y)

    InitFramebuffer(ctx, fb)

    return fb.handle
}

ResizeFramebuffer :: proc(ctx: ^RenderContext, handle: FramebufferHandle, width := 0, height := 0) {
    fb, ok := GetElementPtr(renderCtx.framebuffers, handle)
    if ok {
        DeinitFramebuffer(fb)

        fb.width  = width  if width  != 0 else int(ctx.frameSize.x)
        fb.height = height if height != 0 else int(ctx.frameSize.y)

        InitFramebuffer(ctx, fb)
    }
}

// BUFFER

GPUBufferHandle :: distinct Handle
GPUBuffer :: struct {
    handle: GPUBufferHandle,

    dataPtr: rawptr,
    dataLen: int,

    using backend: GPUBufferBackend,
}

// CreateGPUBuffer :: proc($T: typeid, count: int = 1) -> ^GPUBuffer {
//     ret := CreateElement(&renderContext.buffers)

//     ret.byteSize = size_of(T) * count

//     BackendInitGPUBuffer(ret)
//     return ret
// }

CreateGPUBuffer :: proc(dataStruct: any) -> GPUBufferHandle {
    ret := CreateElement(&renderCtx.buffers)

    ret.dataPtr = dataStruct.data
    ret.dataLen = type_info_of(dataStruct.id).size

    BackendInitGPUBuffer(ret)
    return ret.handle
}

UpdateBufferData :: proc(handle: GPUBufferHandle) {
    buff, ok := GetElementPtr(renderCtx.buffers, handle)
    if ok {
        BackendUpdateBufferData(buff)
    }
}