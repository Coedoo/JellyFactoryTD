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
    grid: []Tile,
    gridX, gridY: int,

    camera: dm.Camera,

    spawnedBuildings: []Building,

    buildingSprites: [BuildingSprites]dm.Sprite,

    selectedBuildingIdx: int,

    prevMousePos: v2,
}

gameState: ^GameState

//////////////

@export
PreGameLoad : dm.PreGameLoad : proc(assets: ^dm.Assets) {
    dm.RegisterAsset("level1.ldtk", dm.RawFileAssetDescriptor{})
    dm.RegisterAsset("tiles.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("buildings.png", dm.TextureAssetDescriptor{})

    dm.RegisterAsset("testTex.png", dm.TextureAssetDescriptor{})
}

@(export)
GameLoad : dm.GameLoad : proc(platform: ^dm.Platform) {
    gameState = dm.AllocateGameData(platform, GameState)

    gameState.camera = dm.CreateCamera(4.8, 8./6.)

    buildingsTex := dm.GetTextureAsset("buildings.png")
    gameState.buildingSprites[.Solar1] = dm.CreateSprite(buildingsTex, dm.RectInt{0, 0, 32, 32})

    LoadGrid()
}

@(export)
GameUpdate : dm.GameUpdate : proc(state: rawptr) {
    gameState = cast(^GameState) state

    // BuildingsWindow()

    // Camera movement
    pos := dm.ScreenToWorldSpace(
            gameState.camera, 
            dm.input.mousePos,
            dm.renderCtx.frameSize
        ).xy

    if dm.GetMouseButton(.Right) == .Down {
        delta := cast([2]f32) gameState.prevMousePos - pos
        gameState.camera.position.xy += delta
    }

    gameState.prevMousePos = cast(v2) dm.ScreenToWorldSpace(
            gameState.camera, 
            dm.input.mousePos,
            dm.renderCtx.frameSize
        ).xy

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
    dm.SetCamera(gameState.camera)

    for tile, idx in gameState.grid {
        dm.DrawSprite(tile.sprite, tile.worldPos)
    }

    if gameState.selectedBuildingIdx != 0 {
        mousePos := dm.ScreenToWorldSpace(gameState.camera, dm.input.mousePos, dm.renderCtx.frameSize)

        gridPos: iv2
        gridPos.x = i32(mousePos.x)
        gridPos.y = i32(mousePos.y)

        building := Buildings[gameState.selectedBuildingIdx - 1]
        sprite := gameState.buildingSprites[building.sprite]
        dm.DrawSprite(sprite, dm.ToV2(gridPos))
    }
}

/////////////////
