package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"
import "core:mem"

EditorState :: struct {
    camera: dm.Camera,

    paintingTileType: TileType,

    isDragging: bool,
    prevMousePos: v2,
}

InitEditor :: proc(state: ^EditorState) {
    state.camera = dm.renderCtx.camera
    DEBUG_TILE_OVERLAY = true
}

EditorUpdate :: proc(state: ^EditorState) {
    // Camera wsad movement

    horizontal := dm.GetAxis(.A, .D)
    vertical := dm.GetAxis(.S, .W)

    moveVec := v2{horizontal, vertical} * dm.time.deltaTime * 10
    state.camera.position += dm.ToV3(moveVec)

    // Camera zoom
    state.camera.orthoSize += -f32(dm.input.scroll) * 0.3
    state.camera.orthoSize = max(1, state.camera.orthoSize)

    // Camera grab
    if dm.GetMouseButton(.Right) == .JustPressed {
        state.isDragging = true
        state.prevMousePos = dm.ScreenToWorldSpace(state.camera, dm.input.mousePos).xy
    }

    if state.isDragging {
        mousePos := dm.ScreenToWorldSpace(state.camera, dm.input.mousePos).xy
        drag := state.prevMousePos - mousePos

        state.camera.position.xy += drag

        state.prevMousePos = dm.ScreenToWorldSpace(state.camera, dm.input.mousePos).xy
    }

    if dm.GetMouseButton(.Right) == .JustReleased {
        state.isDragging = false
    }


    // for i in 0..=len(TileType) {
    //     key := dm.Key(int(dm.Key.Num1) + i)
    //     if dm.GetKeyState(key) == .JustPressed {
    //         state.paintingTileType = TileType(i)
    //     }
    // }

    // if state.paintingTileType != .None && dm.GetMouseButton(.Left) == .Down {
    //     coord := MousePosGrid(state.camera)
    //     tile := GetTileAtCoord(coord)
    //     tile.type = state.paintingTileType
    // }
}

EditorRender :: proc(state: EditorState) {
    dm.SetCamera(state.camera)

    GameplayRender()

    dm.DrawGrid()
}