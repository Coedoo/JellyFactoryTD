#+build js
package dmcore

import gl "vendor:wasm/WebGL"

import "core:mem"
import "core:fmt"

/// SHADERS

_Shader :: struct {
    shaderID: gl.Program
}

CompileShaderSource :: proc(renderCtx: ^RenderContext, name, source: string) -> ShaderHandle {
    @static header := "#version 300 es\n"

    vertShader := gl.CreateShader(gl.VERTEX_SHADER)
    defer gl.DeleteShader(vertShader)

    gl.ShaderSource(vertShader, {header, "#define VERTEX \n", source})
    gl.CompileShader(vertShader)

    buf: [1024]byte

    // @TODO: better errors
    if gl.GetShaderiv(vertShader, gl.COMPILE_STATUS) == 0 {
        error := gl.GetShaderInfoLog(vertShader, buf[:])
        fmt.eprint(error)
        panic("failed compiling vert shader")
    }

    fragShader := gl.CreateShader(gl.FRAGMENT_SHADER)
    defer gl.DeleteShader(fragShader)

    gl.ShaderSource(fragShader, {header, "#define FRAGMENT \n", source})
    gl.CompileShader(fragShader)


    if gl.GetShaderiv(fragShader, gl.COMPILE_STATUS) == 0 {
        error := gl.GetShaderInfoLog(fragShader, buf[:])
        fmt.eprint(error)
        panic("failed compiling frag shader")
    }

    shaderProg := gl.CreateProgram()
    gl.AttachShader(shaderProg, vertShader)
    gl.AttachShader(shaderProg, fragShader)
    gl.LinkProgram(shaderProg)

    if gl.GetProgramParameter(shaderProg, gl.LINK_STATUS) == 0 {
        error := gl.GetProgramInfoLog(shaderProg, buf[:])
        fmt.eprint(error)
        panic("failed linking shader")
    }

    shader := CreateElement(&renderCtx.shaders)
    shader.backend.shaderID = shaderProg
    shader.name = name

    return shader.handle
}

// FRAMEBUFFER

FramebufferBackend :: struct {
    glFramebuffer: gl.Framebuffer,
    textureAttachment: gl.Texture,
}

InitFramebuffer :: proc(ctx: ^RenderContext, fb: ^Framebuffer) {
    fb.glFramebuffer = gl.CreateFramebuffer()
    gl.BindFramebuffer(gl.FRAMEBUFFER, fb.glFramebuffer)

    fb.textureAttachment = gl.CreateTexture()
    gl.BindTexture(gl.TEXTURE_2D, fb.textureAttachment)

    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, i32(fb.width), i32(fb.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, 0, nil)

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.NEAREST))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.NEAREST))

    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, fb.textureAttachment, 0)

    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
    gl.BindTexture(gl.TEXTURE_2D, 0)
}

DeinitFramebuffer :: proc(fb: ^Framebuffer) {
    gl.DeleteFramebuffer(fb.glFramebuffer)
    gl.DeleteTexture(fb.textureAttachment)
}

// UNIFORM BUFFER

GPUBufferBackend :: struct {
    glBuffer: gl.Buffer,
}

BackendInitGPUBuffer :: proc(buff: ^GPUBuffer) {
    buff.glBuffer = gl.CreateBuffer()

    gl.BindBuffer(gl.UNIFORM_BUFFER, buff.glBuffer)
    gl.BufferData(gl.UNIFORM_BUFFER, buff.dataLen, nil, gl.DYNAMIC_DRAW)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)
}

BackendUpdateBufferData :: proc(buff: ^GPUBuffer) {
    gl.BindBuffer(gl.UNIFORM_BUFFER, buff.glBuffer)
    gl.BufferSubData(gl.UNIFORM_BUFFER, 0, buff.dataLen, buff.dataPtr)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)
}