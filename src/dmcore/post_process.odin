package dmcore

PostProcessGlobalData :: struct #align(16) {
    resolution: iv2,
    time: f32,
}

PostProcess :: struct {
    uniformBuffer: GPUBufferHandle,
    shader: ShaderHandle,
}

CreatePostProcess :: proc(shader: ShaderHandle, uniformData: any = nil) -> PostProcess {
    pp: PostProcess
    pp.shader = shader

    if uniformData != nil {
        pp.uniformBuffer = CreateGPUBuffer(uniformData)
        UpdateBufferContent(pp.uniformBuffer)
    }

    return pp
}



// BloomPostPorcess :: proc(bloom: Bloom) {
    // PreparePostPorcess()

    // SetRT(bloom.horizontalRT)
    // DrawPP(bloom.horizontalShader)

    // SetTexture(bloom.horizonatalRT)
    // SetRT(bloom.verticalRT)
    // DrawPP(bloom.verticalShader)

    // SetTexture(bloom.verticalRT)
    // FinishPostProcess()
// }
