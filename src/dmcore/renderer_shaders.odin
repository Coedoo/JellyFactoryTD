package dmcore

DefaultShaderType :: enum {
    Sprite,
    ScreenSpaceRect,
    SDFFont,
    Grid,
}

Shader :: struct {
    handle: ShaderHandle,
    backend: _Shader,
}
