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
    enemies: dm.ResourcePool(EnemyInstance, EnemyHandle),

    selectedBuildingIdx: int,

    /////////////
    // Player character

    playerSprite: dm.Sprite,
    playerPosition: v2,

    path: []iv2,

    ///
    arrowSprite: dm.Sprite,

    selectedTile: iv2,

    buildingWire: bool,
    pushedWire: bool, // @RENAME
    lastPushedCoord: iv2,

    testWave: [dynamic]EnemiesCount,
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

    dm.RegisterAsset("ship.png", dm.TextureAssetDescriptor{})
}

@(export)
GameLoad : dm.GameLoad : proc(platform: ^dm.Platform) {
    gameState = dm.AllocateGameData(platform, GameState)

    gameState.playerSprite = dm.CreateSprite(dm.GetTextureAsset("ship.png"))
    gameState.playerSprite.scale = 2

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
    gameState.arrowSprite.origin = {0, 0.5}

    SpawnEnemy(0)

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

    cursorOverUI := dm.muiIsCursorOverUI(dm.mui, dm.input.mousePos)

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

    scroll := dm.input.scroll if cursorOverUI == false else 0
    camHeight = camHeight - f32(scroll) * 0.3
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
        buildingData := &Buildings[building.dataIdx]

        if .ProduceEnergy in buildingData.flags {
            building.currentEnergy += buildingData.energyProduction * f32(dm.time.deltaTime)
            building.currentEnergy = min(building.currentEnergy, buildingData.energyStorage)

            for connected in building.connectedBuildings {
                other := dm.GetElementPtr(gameState.spawnedBuildings, connected) or_continue
                otherData := Buildings[other.dataIdx]

                if .RequireEnergy in otherData.flags {
                    // @TODO: add flow value
                    energy := 10 * f32(dm.time.deltaTime)

                    toRemove := min(energy, otherData.energyStorage - other.currentEnergy)
                    toRemove = min(toRemove, building.currentEnergy)

                    building.currentEnergy -= toRemove
                    other.currentEnergy += toRemove
                }
            }
        }

        if .Attack in buildingData.flags {
            building.attackTimer -= f32(dm.time.deltaTime)

            handle := FindClosestEnemy(building.position, buildingData.range)
            if handle != {} && 
               building.currentEnergy >= buildingData.energyRequired &&
               building.attackTimer <= 0
            {
                enemy, ok := dm.GetElementPtr(gameState.enemies, handle)
                if ok == false {
                    continue
                }

                building.attackTimer = buildingData.reloadTime

                building.currentEnergy = 0
                enemy.health -= buildingData.damage

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
    if dm.muiBeginWindow(dm.mui, "Buildings", {10, 10, 100, 150}) {
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

    // Cancell building/wire or destroy building
    if dm.GetMouseButton(.Right) == .JustPressed &&
       cursorOverUI == false
    {
        if gameState.selectedBuildingIdx != 0 {
            gameState.selectedBuildingIdx = 0
        }
        else if gameState.buildingWire {
            gameState.buildingWire = false
        }
        else {
            tile := TileUnderCursor()
            RemoveBuilding(tile.building)
        }
    }

    // Wire
    if gameState.buildingWire &&
       cursorOverUI == false
    {
        if dm.GetMouseButton(.Left) == .JustPressed {
            gameState.lastPushedCoord = MousePosGrid()
            gameState.pushedWire = true
        }

        if dm.GetMouseButton(.Left) == .Down {
            coord := MousePosGrid()
            tile := GetTileAtCoord(coord)

            if tile.building == {} && coord != gameState.lastPushedCoord {
                delta := coord - gameState.lastPushedCoord

                test := abs(delta.x) + abs(delta.y)
                if test == 1 {
                    otherTile := GetTileAtCoord(gameState.lastPushedCoord)
                    if delta.x == 1 {
                        tile.wireDir ~= { .West }
                        otherTile.wireDir ~= { .East }
                    }
                    else if delta.x == -1 {
                        tile.wireDir ~= { .East }
                        otherTile.wireDir ~= { .West }
                    }
                    else if delta.y == 1 {
                        tile.wireDir ~= { .South }
                        otherTile.wireDir ~= { .North }
                    }
                    else if delta.y == -1 {
                        tile.wireDir ~= { .North }
                        otherTile.wireDir ~= { .South }
                    }

                    CheckBuildingConnection(coord)
                }
            }

            gameState.lastPushedCoord = coord
        }

        if dm.GetMouseButton(.Left) == .JustReleased {
            gameState.pushedWire = false
        }
    }

    // Highlight Building 
    if gameState.buildingWire == false && gameState.selectedBuildingIdx == 0 && cursorOverUI == false{
        if dm.GetMouseButton(.Left) == .JustPressed {
            coord := MousePosGrid()
            // tile := GetTileAtCoord(coord)

            gameState.selectedTile = coord
        }
    }

    // Building
    if gameState.selectedBuildingIdx != 0 &&
       dm.GetMouseButton(.Left) == .JustPressed &&
       cursorOverUI == false
    {
        pos := MousePosGrid()
        TryPlaceBuilding(gameState.selectedBuildingIdx - 1, pos)
    }


    if dm.muiBeginWindow(dm.mui, "Selected Building", {600, 10, 140, 250}) {
        tile := GetTileAtCoord(gameState.selectedTile)
        dm.muiLabel(dm.mui, tile.wireDir)

        if dm.muiHeader(dm.mui, "Building") {
            if tile.building != {} {
                building, ok := dm.GetElementPtr(gameState.spawnedBuildings, tile.building)
                if ok {
                    data := &Buildings[building.dataIdx]
                    dm.muiLabel(dm.mui, "Name:", data.name)
                    dm.muiLabel(dm.mui, building.handle)
                    dm.muiLabel(dm.mui, "Pos:", building.gridPos)
                    dm.muiLabel(dm.mui, "energy:", building.currentEnergy, "/", data.energyStorage)

                    if dm.muiHeader(dm.mui, "Connected Buildings") {
                        for b in building.connectedBuildings {
                            dm.muiLabel(dm.mui, b)
                        }
                    }
                }
            }
        }

        dm.muiEndWindow(dm.mui)
    }

    // if dm.muiBeginWindow(dm.mui, "Selected Building", {10, 150, 140, 250}) {
    //     for &c in testWave {
             
    //     }

    //     dm.muiEndWindow(dm.mui)
    // }
}

@(export)
GameUpdateDebug : dm.GameUpdateDebug : proc(state: rawptr, debug: bool) {
    gameState = cast(^GameState) state

    if debug {
        if dm.muiBeginWindow(dm.mui, "Config", {10, 200, 150, 100}) {
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

        if DEBUG_TILE_OVERLAY {
            dm.DrawBlankSprite(tile.worldPos, {1, 1}, TileTypeColor[tile.type])
        }
    }

    // Buildings
    for building in gameState.spawnedBuildings.elements {
        // @TODO @CACHE
        data := &Buildings[building.dataIdx]
        tex := dm.GetTextureAsset(data.spriteName)
        sprite := dm.CreateSprite(tex, data.spriteRect)

        pos := building.position
        dm.DrawSprite(sprite, pos)

        if data.energyStorage != 0 {
            dm.DrawWorldRect(
                dm.renderCtx.whiteTexture, 
                dm.ToV2(building.gridPos) + {f32(data.size.y), 0},
                {0.1, building.currentEnergy / data.energyStorage}
            )
        }

        if dm.platform.debugState {
            if .Attack in data.flags {
                dm.DrawCircle(dm.renderCtx, pos, data.range, false)
            }
        }

        // for out in building.outputsPos {
        //     pos := building.position + dm.ToV2(out) * 0.6

        //     rot := math.atan2(f32(out.y), f32(out.x))
        //     dm.DrawSprite(gameState.arrowSprite, pos, rotation = rot)
        // }

        // for input in building.inputsPos {
        //     pos := building.position + dm.ToV2(input) * 0.6

        //     rot := math.atan2(f32(input.y), f32(input.x)) + math.to_radians(f32(180))
        //     dm.DrawSprite(gameState.arrowSprite, pos, rotation = rot)
        // }
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

    if gameState.buildingWire && gameState.pushedWire {
        tile := GetTileAtCoord(gameState.lastPushedCoord)
        for dir in Direction {
            if dir not_in tile.wireDir {
                dm.DrawSprite(gameState.arrowSprite, tile.worldPos, rotation = math.to_radians(DirToRot[dir]))
            }
        }
    }

    // Player
    dm.DrawSprite(gameState.playerSprite, gameState.playerPosition)

    // Enemy
    for &enemy, i in gameState.enemies.elements {
        if gameState.enemies.slots[i].inUse {
            stats := Enemies[enemy.statsIdx]
            color := math.lerp(dm.RED, dm.GREEN, enemy.health / stats.maxHealth)
            dm.DrawBlankSprite(enemy.position, {1, 1}, color = color)
        }
    }

    // path
    for i := 0; i < len(gameState.path) - 1; i += 1 {
        a := gameState.path[i]
        b := gameState.path[i + 1]

        dm.DrawLine(dm.renderCtx, dm.ToV2(a) + {0.5, 0.5}, dm.ToV2(b) + {0.5, 0.5}, false, dm.GREEN)
    }
}
