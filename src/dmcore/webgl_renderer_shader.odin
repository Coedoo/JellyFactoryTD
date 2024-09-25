#+build js
package dmcore

import gl "vendor:wasm/WebGL"

import "core:fmt"

_Shader :: struct {
    shaderID: gl.Program
}

CompileShaderSource :: proc(renderCtx: ^RenderContext, source: string) -> ShaderHandle {
    @static header := "#version 300 es\n"

    vertShader := gl.CreateShader(gl.VERTEX_SHADER)
    defer gl.DeleteShader(vertShader)

    gl.ShaderSource(vertShader, {header, "#define VERTEX \n", source})
    gl.CompileShader(vertShader)

    buf: [1024]byte

    // @TODO: better errors
    if gl.GetShaderiv(vertShader, gl.COMPILE_STATUS) == 0 {
        error := gl.GetShaderInfoLog(vertShader, buf[:])
        fmt.eprintf(error)
        panic("failed compiling vert shader")
    }

    fragShader := gl.CreateShader(gl.FRAGMENT_SHADER)
    defer gl.DeleteShader(fragShader)

    gl.ShaderSource(fragShader, {header, "#define FRAGMENT \n", source})
    gl.CompileShader(fragShader)


    if gl.GetShaderiv(fragShader, gl.COMPILE_STATUS) == 0 {
        error := gl.GetShaderInfoLog(fragShader, buf[:])
        fmt.eprintf(error)
        panic("failed compiling frag shader")
    }

    shaderProg := gl.CreateProgram()
    gl.AttachShader(shaderProg, vertShader)
    gl.AttachShader(shaderProg, fragShader)
    gl.LinkProgram(shaderProg)

    if gl.GetProgramParameter(shaderProg, gl.LINK_STATUS) == 0 {
        panic("failed linking shader")
    }

    shader := CreateElement(&renderCtx.shaders)
    shader.backend.shaderID = shaderProg

    return shader.handle
}