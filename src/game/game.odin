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
    levels: []Level,
    level: Level, // currentLevel

    spawnedBuildings: dm.ResourcePool(BuildingInstance, BuildingHandle),
    enemies: dm.ResourcePool(Enemy, EnemyHandle),

    buildingWire: bool,
    selectedBuildingIdx: int,

    /////////////
    // Player character

    playerSprite: dm.Sprite,
    playerPosition: v2,

    path: []iv2,

    ///
    arrowSprite: dm.Sprite,

    selectedBuilding: BuildingHandle,
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
    dm.RegisterAsset("kenney_tilemap.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("buildings.png", dm.TextureAssetDescriptor{})

    dm.RegisterAsset("jelly.png", dm.TextureAssetDescriptor{})
}

@(export)
GameLoad : dm.GameLoad : proc(platform: ^dm.Platform) {
    gameState = dm.AllocateGameData(platform, GameState)

    gameState.playerSprite = dm.CreateSprite(dm.GetTextureAsset("jelly.png"))

    dm.InitResourcePool(&gameState.spawnedBuildings, 128)
    dm.InitResourcePool(&gameState.enemies, 128)

    gameState.levels = LoadLevels()
    if len(gameState.levels) > 0 {
        gameState.level = gameState.levels[0]
    }

    gameState.playerPosition = dm.ToV2(iv2{gameState.level.sizeX, gameState.level.sizeY}) / 2

    gameState.path = CalculatePath(gameState.level, gameState.level.startCoord, gameState.level.endCoord)
    // fmt.println(gameState.path)

    gameState.arrowSprite = dm.CreateSprite(dm.GetTextureAsset("buildings.png"), dm.RectInt{32 * 2, 0, 32, 32})
    gameState.arrowSprite.scale = 0.4

    enemy := dm.CreateElement(gameState.enemies)
    enemy.speed = 5
    enemy.position = dm.ToV2(gameState.path[0]) + {0.5, 0.5}

    enemy.maxHealth = 100
    enemy.health = enemy.maxHealth

    // Test level
    TryPlaceBuilding(1, {15, 20})
    TryPlaceBuilding(0, {20, 18})

    GetTileAtCoord({16, 20}).wireDir = {.West, .East}
    GetTileAtCoord({17, 20}).wireDir = {.West, .East}
    GetTileAtCoord({18, 20}).wireDir = {.West, .East}
    GetTileAtCoord({19, 20}).wireDir = {.West, .East}
    GetTileAtCoord({20, 20}).wireDir = {.West, .South}
    GetTileAtCoord({20, 19}).wireDir = {.North, .South}


    TryPlaceBuilding(1, {15, 17})
    TryPlaceBuilding(0, {18, 17})

    CheckBuildingConnection({18, 20})
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

    // Camera Control
    camAspect := dm.renderCtx.camera.aspect
    camHeight := dm.renderCtx.camera.orthoSize
    camWidth  := camAspect * camHeight

    levelSize := v2{
        f32(gameState.level.sizeX - 1), // -1 to account for level edge
        f32(gameState.level.sizeY - 1),
    }

    camHeight = camHeight - f32(dm.input.scroll) * 0.3
    camWidth = camAspect * camHeight

    camHeight = clamp(camHeight, 1, levelSize.x / 2)
    camWidth  = clamp(camWidth,  1, levelSize.y / 2)

    camSize := min(camHeight, camWidth / camAspect)
    dm.renderCtx.camera.orthoSize = camSize

    camPos := gameState.playerPosition
    camPos.x = clamp(camPos.x, camWidth + 1,  levelSize.x - camWidth)
    camPos.y = clamp(camPos.y, camHeight + 1, levelSize.y - camHeight)
    dm.renderCtx.camera.position.xy = cast([2]f32) camPos

    // Update Buildings
    for &building in gameState.spawnedBuildings.elements {
        if .ProduceEnergy in building.flags {
            building.currentEnergy += building.energyProduction * f32(dm.time.deltaTime)
            building.currentEnergy = min(building.currentEnergy, building.energyStorage)
        }

        if .Attack in building.flags {
            building.attackTimer -= f32(dm.time.deltaTime)

            handle := FindClosestEnemy(building.position, building.range)
            if handle != {} && 
               building.currentEnergy >= building.energyRequired &&
               building.attackTimer <= 0
            {
                enemy, ok := dm.GetElementPtr(gameState.enemies, handle)
                if ok == false {
                    continue
                }

                building.attackTimer = building.reloadTime

                building.currentEnergy = 0
                enemy.health -= 10

                if enemy.health <= 0 {
                    dm.FreeSlot(gameState.enemies, handle)
                }
            }
        }
    }

    // Update Enemies 
    for &enemy, i in gameState.enemies.elements {
        if gameState.enemies.slots[i].inUse {
            UpdateEnemy(&enemy)
        }
    }


    // temp UI
    if dm.muiBeginWindow(dm.mui, "Buildings", {10, 10, 100, 150}, {}) {
        for b, idx in Buildings {
            if dm.muiButton(dm.mui, b.name) {
                gameState.selectedBuildingIdx = idx + 1
                gameState.buildingWire = false
            }
        }

        if dm.muiButton(dm.mui, "Wire") {
            gameState.buildingWire = true
            gameState.selectedBuildingIdx = 0
        }

        dm.muiEndWindow(dm.mui)
    }

    // Building
    if gameState.selectedBuildingIdx != 0 &&
       dm.GetMouseButton(.Left) == .JustPressed
    {
        pos := MousePosGrid()
        TryPlaceBuilding(gameState.selectedBuildingIdx - 1, pos)
    }


    if dm.GetMouseButton(.Right) == .JustPressed {
        if gameState.selectedBuildingIdx != 0 {
            gameState.selectedBuildingIdx = 0
            gameState.buildingWire = false
        }
        else {
            coord := MousePosGrid()
            tile := GetTileAtCoord(coord)
            if tile != nil {
                RemoveBuilding(tile.building)
            }
        }
    }

    // Wire
    if gameState.buildingWire {
        if dm.GetMouseButton(.Left) == .JustPressed {
            coord := MousePosGrid()
            tile := GetTileAtCoord(coord)

            // if tile != nil {
            //     tile.hasWire = !tile.hasWire
            //     gameState.path = CalculatePath(gameState.level, gameState.level.startCoord, gameState.level.endCoord)
                
            // }
        }
    }

    // dm.test_window(dm.mui)

    // Highlight Building 
    if gameState.buildingWire == false && gameState.selectedBuildingIdx == 0 {
        if dm.GetMouseButton(.Left) == .JustPressed {
            coord := MousePosGrid()
            tile := GetTileAtCoord(coord)

            gameState.selectedBuilding = tile.building
        }
    }

    if gameState.selectedBuilding != {} {
        building, ok := dm.GetElementPtr(gameState.spawnedBuildings, gameState.selectedBuilding)
        if ok {
            if dm.muiBeginWindow(dm.mui, "Selected Building", {600, 10, 140, 250}) {
                dm.muiLabel(dm.mui, "Name:", building.name)
                dm.muiLabel(dm.mui, "Handle:", building.handle)
                dm.muiLabel(dm.mui, "Pos:", building.gridPos)
                dm.muiLabel(dm.mui, "energy:", building.currentEnergy, "/", building.energyStorage)

                if dm.muiHeader(dm.mui, "Connected Buildings") {
                    for b in building.connectedBuildings {
                        dm.muiLabel(dm.mui, b)
                    }
                }

                dm.muiEndWindow(dm.mui)
            }
        }
    }
}

@(export)
GameUpdateDebug : dm.GameUpdateDebug : proc(state: rawptr, debug: bool) {
    gameState = cast(^GameState) state

    if debug {
        if dm.muiBeginWindow(dm.mui, "Config", {10, 200, 150, 100}, {}) {
            dm.muiToggle(dm.mui, "TILE_OVERLAY", &DEBUG_TILE_OVERLAY)

            dm.muiEndWindow(dm.mui)
        }
    }
}

@(export)
GameRender : dm.GameRender : proc(state: rawptr) {
    gameState = cast(^GameState) state
    dm.ClearColor({0.1, 0.1, 0.3, 1})

    // Level

    for tile, idx in gameState.level.grid {
        dm.DrawSprite(tile.sprite, tile.worldPos)

        for dir in tile.wireDir {
            dm.DrawWorldRect(
                dm.renderCtx.whiteTexture,
                tile.worldPos,
                {0.5, 0.1},
                rotation = math.to_radians(DirToRot[dir]),
                color = {0, 0.1, 0.8, 0.5},
                pivot = {0, 0.5}
            )
        }

        if(DEBUG_TILE_OVERLAY) {
            dm.DrawBlankSprite(tile.worldPos, {1, 1}, TileTypeColor[tile.type])
        }
    }

    // Buildings
    for building in gameState.spawnedBuildings.elements {
        // @TODO @CACHE
        tex := dm.GetTextureAsset(building.spriteName)
        sprite := dm.CreateSprite(tex, building.spriteRect)

        pos := building.position
        dm.DrawSprite(sprite, pos)

        if building.energyStorage != 0 {
            dm.DrawWorldRect(
                dm.renderCtx.whiteTexture, 
                dm.ToV2(building.gridPos) + {f32(building.size.y), 0},
                {0.1, building.currentEnergy / building.energyStorage}
            )
        }

        if .Attack in building.flags {
            dm.DrawCircle(dm.renderCtx, pos, building.range, false)
        }

        for out in building.outputsPos {
            pos := building.position + dm.ToV2(out) * 0.6

            rot := math.atan2(f32(out.y), f32(out.x))
            dm.DrawSprite(gameState.arrowSprite, pos, rotation = rot)
        }

        for input in building.inputsPos {
            pos := building.position + dm.ToV2(input) * 0.6

            rot := math.atan2(f32(input.y), f32(input.x)) + math.to_radians(f32(180))
            dm.DrawSprite(gameState.arrowSprite, pos, rotation = rot)
        }
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

    // Enemy
    for &enemy, i in gameState.enemies.elements {
        if gameState.enemies.slots[i].inUse {
            color := math.lerp(dm.RED, dm.GREEN, enemy.health / enemy.maxHealth)
            dm.DrawBlankSprite(enemy.position, {1, 1}, color = color)
        }
    }

    for i := 0; i < len(gameState.path) - 1; i += 1 {
        a := gameState.path[i]
        b := gameState.path[i + 1]

        dm.DrawLine(dm.renderCtx, dm.ToV2(a) + {0.5, 0.5}, dm.ToV2(b) + {0.5, 0.5}, false, dm.GREEN)
    }
}
