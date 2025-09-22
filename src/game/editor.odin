package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"
import "core:mem"

import "core:encoding/json"
import "core:os"

EditorState :: struct {
    mode: EditorMode,

    camera: dm.Camera,

    isDragging: bool,
    prevMousePos: v2,

    pointedCoord: iv2,

    editedLevel: Level,

    // tileset: dm.SpriteAtlas,
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
    EditFlags,
    EditStartPos,
    EditEndPos,
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

NewEditorLevel :: proc(state: ^EditorState) {
    // width := state.newLevelWidth
    // height := state.newLevelHeight

    // state.editedLevel.sizeX = i32(width)
    // state.editedLevel.sizeY = i32(height)

    // state.editedLevel.grid = make([]Tile, width * height)
    // for &tile, i in state.editedLevel.grid {
    //     x := i % width
    //     y := i / width

    //     tile.gridPos = {i32(x), i32(y)}
    // }

    NewLevel(&state.editedLevel, 32, 32)
    // state.editedLevel.tileset = state.editedLevel.tileset
}

InitEditor :: proc(state: ^EditorState) {
    state.camera = dm.renderCtx.camera

    // atlas := dm.GetTextureAsset("kenney_tilemap.png")
    // state.editedLevel.tileset = {
    //     texture  = atlas,
    //     cellSize = {16, 16},
    //     spacing = {1, 1}
    // }

    state.tileFlip = {}

    if state.editedLevel.sizeX == 0 && state.editedLevel.sizeY == 0 {
        NewEditorLevel(state)
    }
}

CloseEditor :: proc(state: ^EditorState) {
    gameState.loadedLevel = state.editedLevel
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
                NewEditorLevel(state)
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
                state.editedLevel.grid[idx].tilesetCoord = state.selectedTilesetTile
                state.editedLevel.grid[idx].tileFlip = state.tileFlip
           }
        }

        if dm.Panel("Tiles") {
            count := dm.GetCellsCount(state.editedLevel.tileset)

            for y in 0..<count.y {
                dm.BeginLayout(fmt.tprint("TilesX", y), axis = .X)
                for x in 0..<count.x {
                    rect := dm.GetSpriteRect(state.editedLevel.tileset, {x, y})

                    dm.PushId(y * count.x + x)
                    // node := dm.UIImage(state.editedLevel.tileset.texture, maybeSize = iv2{40, 40}, source = rect)

                    inter := dm.ImageButtonI(
                        state.editedLevel.tileset.texture,
                        size = iv2{40, 40},
                        texSource = rect)
                    if inter.cursorReleased
                    {
                        state.selectedTilesetTile = {x, y}
                    }
                    dm.PopId()
                }
                dm.EndLayout()
            }

            // dm.UICheckbox("Flip X", &state.tileFlip.x)
            // dm.UICheckbox("Flip Y", &state.tileFlip.y)
        }

    case .EditFlags:
        if isOverUI == false && dm.GetMouseButton(.Left) == .Down {
            coord := state.pointedCoord
            if coord.x >= 0 && coord.x < state.editedLevel.sizeX &&
               coord.y >= 0 && coord.y < state.editedLevel.sizeY
           {
                idx := coord.y * state.editedLevel.sizeX + coord.x
                state.editedLevel.grid[idx].flags += { state.selectedFlag }
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
    case .EditStartPos:
        if isOverUI == false && dm.GetMouseButton(.Left) == .Down {
            state.editedLevel.startCoord = state.pointedCoord
        }

    case .EditEndPos: 
        if isOverUI == false && dm.GetMouseButton(.Left) == .Down {
            state.editedLevel.endCoord = state.pointedCoord
        }
    }

    dm.BeginLayout("PosButtons", axis = .X)
    if dm.UIButton("Start Pos") {
        SwitchMode(state, .EditStartPos)
    }

    if dm.UIButton("End Pos") {
        SwitchMode(state, .EditEndPos)
    }
    dm.EndLayout()

    if dm.UIButton("Save") {
        opt := json.Marshal_Options {
            spec = .JSON5
        }

        when ODIN_DEBUG {
            opt.pretty = true
        }

        data, ok := json.marshal(state.editedLevel, opt = opt, allocator = context.temp_allocator)
        // if ok == .None {
            os.write_entire_file("test_save.json", data)
        // }
    }

    if dm.UIButton("Load") {
        data, ok := os.read_entire_file("test_save.json")
        err := json.unmarshal(data, &state.editedLevel)

        state.editedLevel.tileset.texture = dm.GetTextureAsset(state.editedLevel.tileset.texAssetPath)
    }
}

EditorRender :: proc(state: EditorState) {
    dm.SetCamera(state.camera)
    dm.ClearColor({0, 0, 0, 1})

    // GameplayRender()
    for &tile in state.editedLevel.grid {
        sprite := dm.GetSprite(state.editedLevel.tileset, tile.tilesetCoord)
        sprite.flipX = tile.tileFlip.x
        sprite.flipY = tile.tileFlip.y
        dm.DrawSprite(sprite, CoordToPos(tile.gridPos))
    }

    // for y in 0..< state.editedLevel.sizeY {
    //     for x in 0..< state.editedLevel.sizeX {
    //         idx := y * state.editedLevel.sizeX + x

    //         tile := state.editedLevel.startingGrid[idx]
    //         sprite := dm.GetSprite(state.editedLevel.tileset, tile.tilesetCoord)
    //         sprite.flipX = tile.flip.x
    //         sprite.flipY = tile.flip.y

    //         dm.DrawSprite(sprite, CoordToPos({x, y}))
    //     }
    // }

    switch state.mode {
    case .None:
    case .EditTiles:
        sprite := dm.GetSprite(state.editedLevel.tileset, state.selectedTilesetTile)
        sprite.flipX = state.tileFlip.x
        sprite.flipY = state.tileFlip.y
        dm.DrawSprite(sprite, CoordToPos(state.pointedCoord), color = {1, 1, 1, 0.5})

    case .EditStartPos: fallthrough
    case .EditEndPos:  fallthrough
    case .EditFlags:
        for y in 0..< state.editedLevel.sizeY {
            for x in 0..< state.editedLevel.sizeX {
                idx := y * state.editedLevel.sizeX + x
                tile := state.editedLevel.grid[idx]

                for flag in tile.flags {
                    color := TileFlagColors[flag]
                    color.a = flag == state.selectedFlag ? 0.6 : 0.1
                    dm.DrawRectBlank(CoordToPos({x, y}), {1, 1}, color = color)
                }
            }
        }

        dm.DrawRectBlank(CoordToPos(state.editedLevel.startCoord), {1, 1}, color = dm.GREEN)
        dm.DrawRectBlank(CoordToPos(state.editedLevel.endCoord), {1, 1}, color = dm.RED)

    // case .EditStartPos:
    //     dm.DrawRectBlank(CoordToPos(state.editedLevel.startCoord), {1, 1}, color = dm.GREEN)

    // case .EditEndPos:
    //     dm.DrawRectBlank(CoordToPos(state.editedLevel.endCoord), {1, 1}, color = dm.RED)
    }

    dm.DrawGrid()
}