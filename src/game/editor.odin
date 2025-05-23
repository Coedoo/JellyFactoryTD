package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"
import "core:mem"

EditorState :: struct {
    mode: EditorMode,

    camera: dm.Camera,

    isDragging: bool,
    prevMousePos: v2,

    pointedCoord: iv2,

    editedLevel: Level,

    tileset: dm.SpriteAtlas,
    selectedTilesetTile: iv2,
    tileFlip: [2]bool,

    selectedFlag: TileFlag,

    showNewLevel: bool,
    newLevelWidth:  int,
    newLevelHeight: int,
}

EditorMode :: enum {
    None,
    EditTiles,
    EditFlags
}

TileFlagColors := [TileFlag]dm.color {
    .Walkable     = ({234, 212, 170, 255} / 255.0),
    .HasEnergy    = ({0, 153, 219, 255} / 255.0),
    .NonBuildable = {0.6, 0.6, 0.6, 1},
}

SwitchMode :: proc(state: ^EditorState, newMode: EditorMode) {
    if state.mode == newMode {
        state.mode = .None
    }
    else {
        state.mode = newMode
    }
}

NewLevel :: proc(state: ^EditorState) {
    width := state.newLevelWidth
    height := state.newLevelHeight

    state.editedLevel.sizeX = i32(width)
    state.editedLevel.sizeY = i32(height)

    state.editedLevel.startingGrid = make([]TileDef, width * height)
}

InitEditor :: proc(state: ^EditorState) {
    state.camera = dm.renderCtx.camera

    atlas := dm.GetTextureAsset("kenney_tilemap.png")
    state.tileset = {
        texture  = atlas,
        cellSize = {16, 16},
        spacing = {1, 1}
    }

    state.newLevelWidth  = 32
    state.newLevelHeight = 32
    NewLevel(state)
}

EditorUpdate :: proc(state: ^EditorState) {
    // Camera wsad movement
    horizontal := dm.GetAxis(.A, .D)
    vertical := dm.GetAxis(.S, .W)

    moveVec := v2{horizontal, vertical} * dm.time.deltaTime * 10
    state.camera.position += dm.ToV3(moveVec)

    // Camera zoom
    state.camera.orthoSize += -f32(dm.input.scroll) * 0.6
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

    // Logic
    state.pointedCoord = MousePosGrid(state.camera)

    if dm.UIButton("New Level") {
        state.showNewLevel = !state.showNewLevel
    }

    if state.showNewLevel {
        if dm.Panel("new level", dm.Aligment{.Top, .Right}) {
            dm.UISliderInt("Width", &state.newLevelWidth, 1, 100)
            dm.UILabel(state.newLevelWidth)
            
            // @HACK: @TODO: Slider doesn't get unique ID for some reason
            dm.PushId(2)
            dm.UISliderInt("Height", &state.newLevelHeight, 1, 100)
            dm.UILabel(state.newLevelHeight)
            dm.PopId()

            if dm.UIButton("Ok") {
                NewLevel(state)
                state.showNewLevel = false
            }
        }
    }

    if dm.UIButton("Edit Tiles") {
        SwitchMode(state, .EditTiles)
    }
    if dm.UIButton("Edit Flags") {
        SwitchMode(state, .EditFlags)
    }

    // Painting
    isOverUI := dm.IsPointOverUI(dm.input.mousePos)

    switch state.mode {
    case .None:
    case .EditTiles:
        if dm.GetKeyState(.Q) == .JustPressed {
            state.tileFlip.x = !state.tileFlip.x
        }

        if dm.GetKeyState(.E) == .JustPressed {
            state.tileFlip.y = !state.tileFlip.y
        }

        if isOverUI == false && dm.GetMouseButton(.Left) == .Down {
            coord := state.pointedCoord
            if coord.x >= 0 && coord.x < state.editedLevel.sizeX &&
               coord.y >= 0 && coord.y < state.editedLevel.sizeY
           {
                idx := coord.y * state.editedLevel.sizeX + coord.x
                state.editedLevel.startingGrid[idx].tilesetCoord = state.selectedTilesetTile
                state.editedLevel.startingGrid[idx].flip = state.tileFlip
           }
        }

        if dm.Panel("Tiles") {
            count := dm.GetCellsCount(state.tileset)

            for y in 0..<count.y {
                dm.BeginLayout(axis = .X)
                for x in 0..<count.x {
                    rect := dm.GetSpriteRect(state.tileset, {x, y})

                    dm.PushId(y * count.x + x)
                    // node := dm.UIImage(state.tileset.texture, maybeSize = iv2{40, 40}, source = rect)

                    if ImageButton(
                        state.tileset.texture,
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

    case .EditFlags:
        if isOverUI == false && dm.GetMouseButton(.Left) == .Down {
            coord := state.pointedCoord
            if coord.x >= 0 && coord.x < state.editedLevel.sizeX &&
               coord.y >= 0 && coord.y < state.editedLevel.sizeY
           {
                idx := coord.y * state.editedLevel.sizeX + coord.x
                state.editedLevel.startingGrid[idx].flags += { state.selectedFlag }
           }
        }

        if dm.Panel("Flags", dm.Aligment{.Top, .Left}) {
            for flag in TileFlag {
                if dm.UIButton(fmt.tprint(flag)) {
                    state.selectedFlag = flag
                }
            }

            dm.UILabel("Painting flag:", state.selectedFlag)
        }
    }
}

EditorRender :: proc(state: EditorState) {
    dm.SetCamera(state.camera)
    dm.ClearColor({0, 0, 0, 1})

    // GameplayRender()

    for y in 0..< state.editedLevel.sizeY {
        for x in 0..< state.editedLevel.sizeX {
            idx := y * state.editedLevel.sizeX + x

            tile := state.editedLevel.startingGrid[idx]
            sprite := dm.GetSprite(state.tileset, tile.tilesetCoord)
            sprite.flipX = tile.flip.x
            sprite.flipY = tile.flip.y

            dm.DrawSprite(sprite, CoordToPos({x, y}))
        }
    }

    switch state.mode {
    case .None:
    case .EditTiles:
        sprite := dm.GetSprite(state.tileset, state.selectedTilesetTile)
        sprite.flipX = state.tileFlip.x
        sprite.flipY = state.tileFlip.y
        dm.DrawSprite(sprite, CoordToPos(state.pointedCoord), color = {1, 1, 1, 0.5})
    
    case .EditFlags:
        for y in 0..< state.editedLevel.sizeY {
            for x in 0..< state.editedLevel.sizeX {
                idx := y * state.editedLevel.sizeX + x
                tile := state.editedLevel.startingGrid[idx]

                for flag in tile.flags {
                    color := TileFlagColors[flag]
                    color.a = flag == state.selectedFlag ? 0.6 : 0.1
                    dm.DrawRectBlank(CoordToPos({x, y}), {1, 1}, color = color)
                }
            }
        }
    }

    dm.DrawGrid()
}