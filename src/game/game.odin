package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

import "../ldtk"

v2 :: dm.v2
iv2 :: dm.iv2


GameState :: struct {
    grid: []Tile `fmt:"-"`,
    gridX, gridY: i32,

    spawnedBuildings: [dynamic]BuildingInstance,

    // buildingSprites: [BuildingSprites]dm.Sprite,

    selectedBuildingIdx: int,

    /////////////
    // Player character

    playerSprite: dm.Sprite,
    playerPosition: v2,
}

gameState: ^GameState

//////////////

MousePosGrid :: proc() -> (gridPos: iv2) {
    mousePos := dm.ScreenToWorldSpace(dm.input.mousePos)

    gridPos.x = i32(mousePos.x)
    gridPos.y = i32(mousePos.y)

    return
}

@export
PreGameLoad : dm.PreGameLoad : proc(assets: ^dm.Assets) {
    dm.RegisterAsset("testTex.png", dm.TextureAssetDescriptor{})

    dm.RegisterAsset("level1.ldtk", dm.RawFileAssetDescriptor{})
    dm.RegisterAsset("tiles.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("buildings.png", dm.TextureAssetDescriptor{})

    dm.RegisterAsset("jelly.png", dm.TextureAssetDescriptor{})
}

@(export)
GameLoad : dm.GameLoad : proc(platform: ^dm.Platform) {
    gameState = dm.AllocateGameData(platform, GameState)

    buildingsTex := dm.GetTextureAsset("buildings.png")

    gameState.playerSprite = dm.CreateSprite(dm.GetTextureAsset("jelly.png"))

    LoadGrid()
}

@(export)
GameUpdate : dm.GameUpdate : proc(state: rawptr) {
    gameState = cast(^GameState) state

    // Move Player
    moveVec := v2{
        dm.GetAxis(.A, .D),
        dm.GetAxis(.S, .W)
    }

    if moveVec != {0, 0} {
        moveVec = glsl.normalize(moveVec)

        gameState.playerPosition += moveVec * PLAYER_SPEED * f32(dm.time.deltaTime)
    }

    // Camera Position
    dm.renderCtx.camera.position.xy = cast([2]f32) gameState.playerPosition

    // Building
    if gameState.selectedBuildingIdx != 0 &&
       dm.GetMouseButton(.Left) == .JustPressed
    {
        pos := MousePosGrid()
        TryPlaceBuilding(gameState.selectedBuildingIdx - 1, pos)
    }

    // temp UI
    if dm.muiBeginWindow(dm.mui, "Buildings", {10, 10, 100, 150}, {}) {
        for b, idx in Buildings {
            if dm.muiButton(dm.mui, b.name) {
                gameState.selectedBuildingIdx = idx + 1
            }
        }

        dm.muiText(dm.mui, gameState)

        dm.muiEndWindow(dm.mui)
    }

}

@(export)
GameUpdateDebug : dm.GameUpdateDebug : proc(state: rawptr, debug: bool) {
    gameState = cast(^GameState) state
}

DrawGrid :: proc(size: iv2) {
    for x in 0..<size.x {
        dm.DrawBlankSprite(v2{f32(x) - f32(size.x / 2), 0}, {0.02, 100}, color = dm.BLACK)
    }

    for y in 0..<size.y {
        dm.DrawBlankSprite(v2{0, f32(y) - f32(size.y / 2)}, {100, 0.02}, color = dm.BLACK)
    }
}

@(export)
GameRender : dm.GameRender : proc(state: rawptr) {
    gameState = cast(^GameState) state
    dm.ClearColor({0.1, 0.1, 0.3, 1})

    // Level

    for tile, idx in gameState.grid {
        dm.DrawSprite(tile.sprite, tile.worldPos)
    }

    // Buildings
    for building in gameState.spawnedBuildings {
        // @TODO @CACHE
        tex := dm.GetTextureAsset(building.spriteName)
        sprite := dm.CreateSprite(tex, building.spriteRect)

        dm.DrawSprite(sprite, dm.ToV2(building.gridPos) + dm.ToV2(building.size) / 2)
    }

    // Selected building
    if gameState.selectedBuildingIdx != 0 {
        gridPos := MousePosGrid()

        building := Buildings[gameState.selectedBuildingIdx - 1]

        // @TODO @CACHE
        tex := dm.GetTextureAsset(building.spriteName)
        sprite := dm.CreateSprite(tex, building.spriteRect)

        color := (CanBePlaced(building, gridPos) ?
                 dm.GREEN : 
                 dm.RED)

        dm.DrawSprite(sprite, dm.ToV2(gridPos) + dm.ToV2(building.size) / 2, color = color)
    }

    // Player
    dm.DrawSprite(gameState.playerSprite, gameState.playerPosition)
}
