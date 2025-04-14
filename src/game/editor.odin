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

    editTiles: bool,
    tileSet: dm.SpriteAtlas,
    selectedTilesetTile: iv2,
}

InitEditor :: proc(state: ^EditorState) {
    state.camera = dm.renderCtx.camera

    atlas := dm.GetTextureAsset("kenney_tilemap.png")
    state.tileSet = {
        texture  = atlas,
        cellSize = {16, 16},
        spacing = {1, 1}
    }
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

    if dm.UIButton("Edit Tiles") {
        state.editTiles = !state.editTiles
    }

    // Painting
    if state.editTiles {
        isOverUI := dm.IsPointOverUI(dm.input.mousePos)
        if isOverUI == false && dm.GetMouseButton(.Left) == .Down {
            coord := MousePosGrid(state.camera)
            tile := GetTileAtCoord(coord)

            if tile != nil  {
                sprite := dm.GetSprite(state.tileSet, state.selectedTilesetTile)
                tile.sprite = sprite
            }
        }

        if dm.Panel("Tiles") {
            count := dm.GetCellsCount(state.tileSet)

            for y in 0..<count.y {
                dm.BeginLayout(axis = .X)
                for x in 0..<count.x {
                    rect := dm.GetSpriteRect(state.tileSet, {x, y})

                    dm.PushId(y * count.x + x)
                    // node := dm.UIImage(state.tileSet.texture, maybeSize = iv2{40, 40}, source = rect)

                    if ImageButton(
                        state.tileSet.texture,
                        maybeSize = iv2{40, 40},
                        texSource = rect)
                    {
                        state.selectedTilesetTile = {x, y}
                    }
                    dm.PopId()
                }
                dm.EndLayout()
            }
        }
    }
}

EditorRender :: proc(state: EditorState) {
    dm.SetCamera(state.camera)
    dm.ClearColor({0, 0, 0, 1})

    GameplayRender()

    dm.DrawGrid()
}