package dmcore

import math "core:math/linalg/glsl"

import "core:fmt"

Camera :: struct {
    position: v3,

    orthoSize: f32,

    near, far, f32,

    aspect: f32,
}

CreateCamera :: proc(orthoSize, aspect:f32, near:f32 = 0.0001, far:f32 = 10000) -> Camera {
    return Camera {
        orthoSize = orthoSize,
        aspect = aspect,
        near = near,
        far = far,
        position = {0, 0, 1},
    }
}


// @TODO: actual view matrix...
GetViewMatrix :: proc(camera: Camera) -> mat4 {
    view := math.mat4Translate(-camera.position)
    return view
}

Mat4OrthoZTO :: proc(left, right, bottom, top, near, far: f32) -> (m: mat4) {
    m[0, 0] = +2 / (right - left)
    m[1, 1] = +2 / (top - bottom)
    m[2, 2] = -1 / (far - near)
    m[0, 3] = -(right + left)   / (right - left)
    m[1, 3] = -(top   + bottom) / (top - bottom)
    m[2, 3] = -near / (far - near)
    m[3, 3] = 1
    return m
}

// @TODO: support perspective projection
GetProjectionMatrixZTO :: proc(camera: Camera) -> mat4 {
    orthoHeight := camera.orthoSize
    orthoWidth  := camera.aspect * orthoHeight

    proj := Mat4OrthoZTO(-orthoWidth, orthoWidth, 
                         -orthoHeight, orthoHeight, 
                          camera.near, camera.far)

    return proj 
}

GetProjectionMatrixNTO :: proc(camera: Camera) -> mat4 {
    orthoHeight := camera.orthoSize
    orthoWidth  := camera.aspect * orthoHeight

    proj := math.mat4Ortho3d(-orthoWidth, orthoWidth, 
                             -orthoHeight, orthoHeight, 
                              camera.near, camera.far)

    return proj
}

GetVPMatrix :: proc(camera: Camera) -> mat4 {
    orthoHeight := camera.orthoSize
    orthoWidth  := camera.aspect * orthoHeight

    proj := math.mat4Ortho3d(-orthoWidth, orthoWidth, 
                             -orthoHeight, orthoHeight, 
                              camera.near, camera.far)

    view := math.mat4Translate(-camera.position)

    return proj * view
}

WorldToClipSpace :: proc(camera: Camera, point: v3) -> v3 {
    p := GetVPMatrix(camera) * v4{point.x, point.y, point.z, 1}
    p.xyz /= p.w

    return p.xyz
}

ScreenToWorldSpace :: proc {
    ScreenToWorldSpaceCtx,
    ScreenToWorldSpaceImpl
}

ScreenToWorldSpaceImpl :: proc(point: iv2) -> v3 {
    return ScreenToWorldSpaceCtx(renderCtx.camera, point, renderCtx.frameSize)
}

ScreenToWorldSpaceCtx :: proc(camera: Camera, point: iv2, screenSize: iv2) -> v3 {
    clip := v2{f32(point.x) / f32(screenSize.x), f32(point.y) / f32(screenSize.y)}
    clip = clip * 2 - 1

    // @TODO: I don't understand why it works....
    vp := GetVPMatrix(camera)
    p := math.inverse(vp) * v4{clip.x, -clip.y, 0, 1}

    return v3{p.x, p.y, p.z}
}

GetCameraBounds :: proc(camera: Camera) -> Bounds2D {
    orthoHeight := camera.orthoSize
    orthoWidth  := camera.aspect * orthoHeight

    return Bounds2D {
        left  = camera.position.x - orthoWidth,
        right = camera.position.x + orthoWidth,
        bot   = camera.position.y - orthoHeight,
        top   = camera.position.y + orthoHeight,
    }
}

ControlCamera :: proc(camera: ^Camera) {
    horizontal := GetAxis(.A, .D)
    vertical   := GetAxis(.W, .S)

    camera.position += {horizontal, -vertical, 0} * f32(time.deltaTime)
}

IsPointInCamera :: proc(point: v3) -> bool {
    return (point.x >= -1 && point.x <= 1) &&
           (point.y >= -1 && point.y <= 1) &&
           (point.z >= -1 && point.z <= 1)
}

IsInsideCamera :: proc {
    IsInsideCamera_Rect,
    IsInsideCamera_Sprite,
}

IsInsideCamera_Rect :: proc(camera: Camera, rect: Rect) -> bool {
    a := v2{rect.x,              rect.y}
    b := v2{rect.x,              rect.y + rect.height}
    c := v2{rect.x + rect.width, rect.y}
    d := v2{rect.x + rect.width, rect.y + rect.width}

    ac := WorldToClipSpace(camera, ToV3(a))
    bc := WorldToClipSpace(camera, ToV3(b))
    cc := WorldToClipSpace(camera, ToV3(c))
    dc := WorldToClipSpace(camera, ToV3(d))

    // fmt.println(ac, bc, cc, dc)

    return IsPointInCamera(ac) ||
           IsPointInCamera(bc) ||
           IsPointInCamera(cc) ||
           IsPointInCamera(dc)
}

IsInsideCamera_Sprite :: proc(camera: Camera, position: v2, sprite: Sprite) -> bool {
    size := GetSpriteSize(sprite)

    offset := sprite.origin * size
    return IsInsideCamera_Rect(camera, {position.x - offset.x, position.y - offset.y, size.x, size.y})
}