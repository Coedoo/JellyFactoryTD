package dmcore

// import "core:fmt"
// import "core:mem"

// CommandBuffer :: struct {
//     commands: [dynamic]Command
// }

// Command :: union {
//     ClearColorCommand,
//     CameraCommand,

//     DrawRectCommand,
//     DrawMeshCommand,
//     DrawGridCommand,

//     PushShaderCommand,
//     PopShaderCommand,

//     BeginScreenSpaceCommand,
//     EndScreenSpaceCommand,

//     BindFBAsTextureCommand,
//     BindRenderTargetCommand,

//     BeginPPCommand,
//     FinishPPCommand,
//     DrawPPCommand,

//     BindBufferCommand,

//     UpdateBufferContentCommand,
// }

// ClearColorCommand :: struct {
//     clearColor: color
// }

// CameraCommand :: struct {
//     camera: Camera
// }

// DrawRectCommand :: struct {
//     position: v2,
//     size: v2,
//     rotation: f32,

//     pivot: v2,

//     texSource: RectInt,
//     tint: color,

//     texture: TexHandle,
//     shader: ShaderHandle,
// }

// DrawMeshCommand :: struct {
//     mesh: ^Mesh,
//     position: v2,
//     shader: ShaderHandle,
// }

// DrawGridCommand :: struct{}

// PushShaderCommand :: struct {
//     shader: ShaderHandle,
// }

// PopShaderCommand :: struct {}

// SetShaderDataCommand :: struct {
//     slot: int,
//     data: rawptr,
//     dataSize: int,
// }

// BeginScreenSpaceCommand :: struct {}
// EndScreenSpaceCommand :: struct {}

// BindFBAsTextureCommand :: struct {
//     framebuffer: FramebufferHandle,
//     slot: int,
// }

// BindRenderTargetCommand :: struct {
//     framebuffer: FramebufferHandle,
// }

// BeginPPCommand :: struct{}
// FinishPPCommand :: struct{}

// DrawPPCommand :: struct {
//     shader: ShaderHandle,
// }

// UpdateBufferContentCommand :: struct {
//     buffer: GPUBufferHandle,
// }

// BindBufferCommand :: struct {
//     buffer: GPUBufferHandle,
//     slot: int,
// }

// ClearColor :: proc(color: color) {
//     ClearColorCtx(renderCtx, color)
// }

// ClearColorCtx :: proc(ctx: ^RenderContext, color: color) {
//     append(&ctx.commandBuffer.commands, ClearColorCommand {
//         color
//     })
// }

// DrawSprite :: proc(sprite: Sprite, position: v2, 
//     rotation: f32 = 0, color := WHITE)
// {
//     texPos := sprite.texturePos
//     texSize := GetTextureSize(sprite.texture)

//     if sprite.animDirection == .Horizontal {
//         texPos.x += sprite.textureSize.x * sprite.currentFrame
//         if texPos.x >= texSize.x {
//             texPos.x = texPos.x % max(texSize.x, 1)
//         }
//     }
//     else {
//         texPos.y += sprite.textureSize.y * sprite.currentFrame
//         if texPos.y >= texSize.y {
//             texPos.y = texPos.y % max(texSize.y, 1)
//         }
//     }

//     size := GetSpriteSize(sprite)

//     // @TODO: flip will be incorrect for every sprite that doesn't
//     // use {0.5, 0.5} as origin
//     flip := v2{sprite.flipX ? -1 : 1, sprite.flipY ? -1 : 1}

//     cmd: DrawRectCommand

//     cmd.position = position
//     cmd.pivot = sprite.origin
//     cmd.size = size * flip
//     cmd.texSource = {texPos.x, texPos.y, sprite.textureSize.x, sprite.textureSize.y}
//     cmd.rotation = rotation
//     cmd.tint = color * sprite.tint
//     cmd.texture = sprite.texture
//     cmd.shader  = renderCtx.defaultShaders[.Sprite]

//     append(&renderCtx.commandBuffer.commands, cmd)
// }

// DrawRect :: proc {
//     DrawRectPos,

//     DrawRectSrcDst,
//     DrawRectBlank,
// }

// DrawRectSrcDst :: proc(texture: TexHandle,
//                  source: RectInt, dest: Rect, shader: ShaderHandle,
//                  origin := v2{0.5, 0.5},
//                  rotation: f32 = 0,
//                  color: color = WHITE)
// {
//     cmd: DrawRectCommand

//     size := v2{dest.width, dest.height}

//     cmd.position = {dest.x, dest.y}
//     cmd.rotation = rotation
//     cmd.size = size
//     cmd.texSource = source
//     cmd.tint = color
//     cmd.pivot = origin

//     cmd.texture = texture
//     cmd.shader =  shader

//     append(&renderCtx.commandBuffer.commands, cmd)
// }

// DrawRectPos :: proc(texture: TexHandle, position: v2,
//                 size: Maybe(v2) = nil, 
//                 origin := v2{0.5, 0.5},
//                 rotation: f32 = 0,
//                 color: color = WHITE)
// {
//     texSize := GetTextureSize(texture)
//     destSize := size.? or_else ToV2(texSize.x)

//     src := RectInt{ 0, 0, texSize.x, texSize.y}
//     dest := Rect{ position.x, position.y, destSize.x, destSize.y }

//     shader := renderCtx.defaultShaders[.Sprite]

//     DrawRectSrcDst(texture, src, dest, shader, origin, rotation, color)
// }

// DrawRectBlank :: proc(position: v2, size: v2,
//                      origin := v2{0.5, 0.5},
//                      rotation: f32 = 0,
//                      color: color = WHITE)
// {
//     DrawRectPos(renderCtx.whiteTexture, position, size, origin, rotation, color)
// }

// SetCamera :: proc(camera: Camera) {
//     append(&renderCtx.commandBuffer.commands, CameraCommand{
//         camera
//     })
// }

// DrawMesh :: proc(mesh: ^Mesh, pos: v2, shader: ShaderHandle) {
//     append(&renderCtx.commandBuffer.commands, DrawMeshCommand{
//         mesh = mesh,
//         position = pos,
//         shader = shader,
//     });
// }

// DrawGrid :: proc() {
//     append(&renderCtx.commandBuffer.commands, DrawGridCommand{})
// }

// PushShader :: proc(shader: ShaderHandle) {
//     append(&renderCtx.commandBuffer.commands, PushShaderCommand{
//         shader = shader
//     })
// }

// PopShader :: proc() {
//     append(&renderCtx.commandBuffer.commands, PopShaderCommand{})
// }

// BeginScreenSpace :: proc() {
//     append(&renderCtx.commandBuffer.commands, BeginScreenSpaceCommand{})
//     renderCtx.inScreenSpace = true
// }


// EndScreenSpace :: proc() {
//     append(&renderCtx.commandBuffer.commands, EndScreenSpaceCommand{})

//     // TODO: cameras stack or something
//     SetCamera(renderCtx.camera)
//     renderCtx.inScreenSpace = false
// }

// UpdateBufferContent :: proc(buffer: GPUBufferHandle) {
//     cmd := UpdateBufferContentCommand {
//         buffer = buffer
//     }

//     append(&renderCtx.commandBuffer.commands, cmd)
// }

// BindBuffer :: proc(buffer: GPUBufferHandle, slot: int) {
//     cmd := BindBufferCommand {
//         buffer = buffer,
//         slot = slot,
//     }

//     append(&renderCtx.commandBuffer.commands, cmd)
// }

// BindFramebufferAsTexture :: proc(framebuffer: FramebufferHandle, slot: int) {
//     cmd := BindFBAsTextureCommand {
//         framebuffer = framebuffer,
//         slot = slot,
//     }

//     append(&renderCtx.commandBuffer.commands, cmd)
// }

// BindRenderTarget :: proc(framebuffer: FramebufferHandle) {
//     cmd := BindRenderTargetCommand {
//         framebuffer = framebuffer,
//     }

//     append(&renderCtx.commandBuffer.commands, cmd)
// }

// BeginPP :: proc() {
//     cmd := BeginPPCommand{}
//     append(&renderCtx.commandBuffer.commands, cmd)
// }

// FinishPP :: proc() {
//     cmd := FinishPPCommand{}

//     append(&renderCtx.commandBuffer.commands, cmd)
// }

// DrawPP :: proc(pp: PostProcess) {
//     cmd := DrawPPCommand {
//         shader = pp.shader
//     }

//     if pp.uniformBuffer != {} {
//         BindBuffer(pp.uniformBuffer, 1)
//     }

//     append(&renderCtx.commandBuffer.commands, cmd)
// }