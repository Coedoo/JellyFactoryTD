package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"
import "core:mem"

import "../ldtk"

v2 :: dm.v2
iv2 :: dm.iv2


GameState :: struct {
    levelArena: mem.Arena,
    levelAllocator: mem.Allocator,

    levels: []Level,
    level: ^Level, // currentLevel

    using levelState: struct {
        spawnedBuildings: dm.ResourcePool(BuildingInstance, BuildingHandle),
        enemies: dm.ResourcePool(EnemyInstance, EnemyHandle),
        energyPackets: dm.ResourcePool(EnergyPacket, EnergyPacketHandle),

        selectedBuildingIdx: int,

        money: int,
        hp: int,

        playerPosition: v2,

        path: []iv2,

        selectedTile: iv2,

        buildingWire: bool,
        buildingWireDir: DirectionSet,

        destroyMode: bool,

        currentWaveIdx: int,
        levelWaves: LevelWaves,
        wavesState: []WaveState,

        levelFullySpawned: bool,

        pathsBetweenBuildings: map[PathKey][]iv2,

        // VFX
        turretFireParticle: dm.ParticleSystem
    },

    playerSprite: dm.Sprite,
    arrowSprite: dm.Sprite,
}

gameState: ^GameState

RemoveMoney :: proc(amount: int) -> bool {
    if gameState.money >= amount {
        gameState.money -= amount
        return true
    }

    return false
}

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
    dm.RegisterAsset("turret_test_3.png", dm.TextureAssetDescriptor{})

    dm.RegisterAsset("ship.png", dm.TextureAssetDescriptor{})
}

@(export)
GameLoad : dm.GameLoad : proc(platform: ^dm.Platform) {
    gameState = dm.AllocateGameData(platform, GameState)

    levelMem := make([]byte, LEVEL_MEMORY)
    mem.arena_init(&gameState.levelArena, levelMem)
    gameState.levelAllocator = mem.arena_allocator(&gameState.levelArena)

    gameState.playerSprite = dm.CreateSprite(dm.GetTextureAsset("ship.png"))
    gameState.playerSprite.scale = 2

    gameState.levels = LoadLevels()
    OpenLevel(START_LEVEL)

    gameState.arrowSprite = dm.CreateSprite(dm.GetTextureAsset("buildings.png"), dm.RectInt{32 * 2, 0, 32, 32})
    gameState.arrowSprite.scale = 0.4
    gameState.arrowSprite.origin = {0, 0.5}

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
    buildingIt := dm.MakePoolIter(&gameState.spawnedBuildings)
    for building in dm.PoolIterate(&buildingIt) {
        buildingData := &Buildings[building.dataIdx]

        if .ProduceEnergy in buildingData.flags {
            produced := buildingData.energyProduction * f32(dm.time.deltaTime)

            currentEnergy := BuildingEnergy(building)
            storageLeft := buildingData.energyStorage - currentEnergy
            produced = min(produced, storageLeft)

            building.currentEnergy[buildingData.producedEnergyType] += produced
        }

        if .SendsEnergy in buildingData.flags {
            building.packetSpawnTimer -= f32(dm.time.deltaTime)
        }

        if .RequireEnergy in buildingData.flags {

            // the loop here is weird because I want to start
            // the iteration from next unused energy source
            // to prevent situations where building is
            // supplied energy from just one source
            // which happened to be updated first

            for i := 0; i < len(building.energySources); i += 1 {

                idx := (building.lastUsedSourceIdx + i) % len(building.energySources)
                sourceHandle := building.energySources[idx]

                source := dm.GetElementPtr(gameState.spawnedBuildings, sourceHandle) or_continue
                sourceData := Buildings[source.dataIdx]

                if .SendsEnergy in sourceData.flags {
                    energyInTransit := GetTransitEnergy(building.handle)

                    sourceEnergy := BuildingEnergy(source)

                    targetEnergy := BuildingEnergy(building)
                    canSpawn := source.packetSpawnTimer <= 0
                    canSpawn &&= sourceEnergy >= sourceData.packetSize
                    canSpawn &&= (buildingData.energyStorage - targetEnergy - energyInTransit) >= sourceData.packetSize

                    if len(building.energySources) > 1 {
                        canSpawn &&= building.lastUsedSourceIdx != idx
                    }

                    if canSpawn {
                        source.packetSpawnTimer = sourceData.packetSpawnInterval

                        packet := dm.CreateElement(&gameState.energyPackets)
                        pathKey := PathKey{
                            from = source.handle,
                            to = building.handle,
                        }

                        // fmt.println(packet.handle)
                        // fmt.println(gameState.energyPackets.slots[packet.handle.index])

                        packet.path = gameState.pathsBetweenBuildings[pathKey]
                        packet.position = CoordToPos(packet.path[0])
                        packet.speed = 6
                        packet.energyType = sourceData.producedEnergyType
                        packet.energy = sourceData.packetSize
                        packet.pathKey = pathKey

                        source.currentEnergy[buildingData.producedEnergyType] -= sourceData.packetSize

                        building.lastUsedSourceIdx = idx
                    }
                }
            }
        }

        if .RotatingTurret in buildingData.flags {
            enemy, ok := dm.GetElementPtr(gameState.enemies, building.targetEnemy)
            if ok {
                delta := building.position - enemy.position
                building.turretAngle = math.atan2(delta.y, delta.x) + math.PI / 2
            }
        }

        if .Attack in buildingData.flags {
            building.attackTimer -= f32(dm.time.deltaTime)

            handle := FindClosestEnemy(building.position, buildingData.range)
            building.targetEnemy = handle

            currentEnergy := BuildingEnergy(building)
            if handle != {} && 
               currentEnergy >= buildingData.energyRequired &&
               building.attackTimer <= 0
            {
                enemy, ok := dm.GetElementPtr(gameState.enemies, handle)
                if ok == false {
                    continue
                }

                building.attackTimer = buildingData.reloadTime

                angle := building.turretAngle + math.PI / 2
                delta := v2 {
                    math.cos(angle),
                    math.sin(angle),
                }

                dm.SpawnParticles(&gameState.turretFireParticle, 10, building.position + delta)

                // building.currentEnergy -= buildingData.energyRequired
                RemoveEnergyFromBuilding(building, buildingData.energyRequired)

                switch buildingData.attackType {
                case .Simple:
                    DamageEnemy(enemy, buildingData.damage)

                case .Cannon:
                    enemies := FindEnemiesInRange(enemy.position, buildingData.attackRadius)
                    for e in enemies {
                        enemy, ok := dm.GetElementPtr(gameState.enemies, e)
                        if ok == false {
                            continue
                        }

                        DamageEnemy(enemy, buildingData.damage)
                    }
                case .None:
                    assert(false) // TODO: Error handling/logger
                }
            }
        }
    }

    // Update Energy
    packetIt := dm.MakePoolIter(&gameState.energyPackets)
    for packet in dm.PoolIterate(&packetIt) {
        if UpdateFollower(packet, packet.speed) {
            building, ok := dm.GetElementPtr(gameState.spawnedBuildings, packet.pathKey.to)
            if ok {
                building.currentEnergy[packet.energyType] += packet.energy
            }

            dm.FreeSlot(&gameState.energyPackets, packet.handle)
        }
    }

    // Update Enemies 
    enemyIt := dm.MakePoolIter(&gameState.enemies)
    for enemy in dm.PoolIterate(&enemyIt) {
        UpdateEnemy(enemy)
    }

    // Wave
    fullySpawnedWavesCount := 0
    for i := 0; i < gameState.currentWaveIdx; i += 1 {
        if gameState.wavesState[i].fullySpawned {
            fullySpawnedWavesCount += 1
            continue
        }

        spawnedCount := 0
        comb := soa_zip(
            state = gameState.wavesState[i].seriesStates, 
            series = gameState.levelWaves.waves[i],
        )

        for &v in comb {
            if v.state.fullySpawned {
                spawnedCount += 1
                continue
            }

            v.state.timer += f32(dm.time.deltaTime)

            if v.state.timer >= v.series.timeBetweenSpawns
            {
                SpawnEnemy(v.series.enemyName)
                v.state.timer = 0
                v.state.count += 1

                if v.state.count >= v.series.count {
                    v.state.fullySpawned = true
                }
            }
        }

        if spawnedCount >= len(gameState.levelWaves.waves[i]) {
            gameState.wavesState[i].fullySpawned = true
            fmt.println("Wave", i, "Fully Spawned");
        }
    }

    if gameState.levelFullySpawned == false && 
       fullySpawnedWavesCount == len(Waves)
    {
        fmt.println("All waves Spawned")
        gameState.levelFullySpawned = true
    }

    // temp UI
    if dm.muiBeginWindow(dm.mui, "GAME MENU", {10, 10, 110, 450}) {
        dm.muiLabel(dm.mui, "Money:", gameState.money)
        dm.muiLabel(dm.mui, "HP:", gameState.hp)

        for b, idx in Buildings {
            if dm.muiButton(dm.mui, b.name) {
                gameState.selectedBuildingIdx = idx + 1
                gameState.buildingWire = false
            }
        }

        dm.muiLabel(dm.mui, "Wires:")
        if dm.muiButton(dm.mui, "Stright") {
            gameState.buildingWire = true
            gameState.selectedBuildingIdx = 0

            gameState.buildingWireDir = DirVertical
        }
        if dm.muiButton(dm.mui, "Angled") {
            gameState.buildingWire = true
            gameState.selectedBuildingIdx = 0

            gameState.buildingWireDir = DirNE
        }
        if dm.muiButton(dm.mui, "Triple") {
            gameState.buildingWire = true
            gameState.selectedBuildingIdx = 0

            gameState.buildingWireDir = {.South, .North, .East}
        }
        if dm.muiButton(dm.mui, "Quad") {
            gameState.buildingWire = true
            gameState.selectedBuildingIdx = 0

            gameState.buildingWireDir = DirSplitter
        }

        dm.muiLabel(dm.mui)
        if dm.muiButton(dm.mui, "Destroy") {
            gameState.destroyMode = true
        }


        dm.muiLabel(dm.mui, "Wave Idx:", gameState.currentWaveIdx, "/", len(gameState.levelWaves.waves))
        if dm.muiButton(dm.mui, "SpawnWave") {
            StartNextWave()
        }

        if dm.muiButton(dm.mui, "Reset level") {
            name := gameState.level.name
            OpenLevel(name)
        }

        dm.muiLabel(dm.mui, "LEVELS:")
        for l in gameState.levels {
            if dm.muiButton(dm.mui, l.name) {
                OpenLevel(l.name)
            }
        }


        dm.muiEndWindow(dm.mui)
    }


    // Destroy structres
    if gameState.destroyMode &&
       dm.GetMouseButton(.Left) == .JustPressed &&
       cursorOverUI == false
    {
        tile := TileUnderCursor()
        if tile.building != {} {
            RemoveBuilding(tile.building)
        }

        if tile.wireDir != {} {
            connectedBuildings := GetConnectedBuildings(tile.gridPos, context.temp_allocator)
            tile.wireDir = nil

            for handleA in connectedBuildings {
                buildingA := dm.GetElementPtr(gameState.spawnedBuildings, handleA) or_continue
                #reverse for handleB, i in buildingA.energyTargets {
                    buildingB := dm.GetElementPtr(gameState.spawnedBuildings, handleB) or_continue

                    key := PathKey{buildingA.handle, buildingB.handle}
                    newPath := CalculatePath(buildingA.gridPos, buildingB.gridPos, WirePredicate)

                    oldPath, ok := gameState.pathsBetweenBuildings[key]
                    if ok {
                        if key.from == handleA || key.to == handleA {
                            it := dm.MakePoolIterReverse(&gameState.energyPackets)
                            for packet in dm.PoolIterate(&it) {
                                if packet.pathKey == key {
                                    dm.FreeSlot(&gameState.energyPackets, packet.handle)
                                }
                            }

                            delete_key(&gameState.pathsBetweenBuildings, key)
                        }

                        delete(oldPath)
                    }

                    if newPath != nil {
                        gameState.pathsBetweenBuildings[key] = newPath
                    }
                    else {
                        delete_key(&gameState.pathsBetweenBuildings, key)
                        unordered_remove(&buildingA.energyTargets, i)
                    }
                }
            }
        }
    }

    if dm.GetMouseButton(.Right) == .JustPressed &&
       cursorOverUI == false
    {
        gameState.selectedBuildingIdx = 0
        gameState.buildingWire = false
        gameState.destroyMode = false
    }

    // Wire
    if gameState.buildingWire &&
       cursorOverUI == false
    {
        @static prevCoord: iv2

        leftBtn := dm.GetMouseButton(.Left)
        if leftBtn == .Down {
            coord := MousePosGrid()

            if prevCoord != coord {
                tile := GetTileAtCoord(coord)
                if tile.building == {} && tile.wireDir != gameState.buildingWireDir {
                    tile.wireDir = gameState.buildingWireDir
                    CheckBuildingConnection(tile.gridPos)
                }

                prevCoord = coord
            }
        }

        if dm.GetKeyState(.Q) == .JustReleased {
            newSet: DirectionSet
            for dir in gameState.buildingWireDir {
                newSet += { NextDir[dir] }
            }
            gameState.buildingWireDir = newSet
        }
    }

    // Highlight Building 
    if gameState.buildingWire == false && gameState.selectedBuildingIdx == 0 && cursorOverUI == false{
        if dm.GetMouseButton(.Left) == .JustPressed {
            coord := MousePosGrid()
            gameState.selectedTile = coord
        }
    }

    // Building
    if gameState.selectedBuildingIdx != 0 &&
       dm.GetMouseButton(.Left) == .JustPressed &&
       cursorOverUI == false
    {
        idx := gameState.selectedBuildingIdx - 1
        building := Buildings[idx]

        pos := MousePosGrid()
        if CanBePlaced(building, pos) {
            if RemoveMoney(building.cost) {
                PlaceBuilding(idx, pos)
            }
        }
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

                    if dm.muiHeader(dm.mui, "Energy Targets") {
                        for b in building.energyTargets {
                            dm.muiLabel(dm.mui, b)
                        }
                    }

                    if dm.muiHeader(dm.mui, "Energy Sources") {
                        for b in building.energySources {
                            dm.muiLabel(dm.mui, b)
                        }
                    }
                }
            }
        }

        dm.muiEndWindow(dm.mui)
    }
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

        // Wire
        for dir in tile.wireDir {
            dm.DrawWorldRect(
                dm.renderCtx.whiteTexture,
                tile.worldPos,
                {0.5, 0.1},
                rotation = math.to_radians(DirToRot[dir]),
                color = {0, 0.1, 0.8, 0.9},
                pivot = {0, 0.5}
            )
        }

        if DEBUG_TILE_OVERLAY {
            dm.DrawBlankSprite(tile.worldPos, {1, 1}, TileTypeColor[tile.type])
        }
    }

    // Buildings
    for &building in gameState.spawnedBuildings.elements {
        // @TODO @CACHE
        buildingData := &Buildings[building.dataIdx]
        tex := dm.GetTextureAsset(buildingData.spriteName)
        sprite := dm.CreateSprite(tex, buildingData.spriteRect)

        pos := building.position
        dm.DrawSprite(sprite, pos)

        // if buildingData.energyStorage != 0 {
        //     // @TODO this breaks batching
        //     dm.DrawWorldRect(
        //         dm.renderCtx.whiteTexture, 
        //         dm.ToV2(building.gridPos) + {f32(buildingData.size.y), 0},
        //         {0.1, building.currentEnergy / buildingData.energyStorage}
        //     )
        // }

        if .RotatingTurret in buildingData.flags {
            sprite := dm.CreateSprite(tex, buildingData.turretSpriteRect)
            sprite.origin = buildingData.turretSpriteOrigin
            dm.DrawSprite(sprite, pos, rotation = building.turretAngle)
        }

        if dm.platform.debugState {
            if .Attack in buildingData.flags {
                dm.DrawCircle(dm.renderCtx, pos, buildingData.range, false)
            }
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

    // Building Wire
    if gameState.buildingWire {
        coord := MousePosGrid()
        for dir in gameState.buildingWireDir {
            dm.DrawWorldRect(
                dm.renderCtx.whiteTexture,
                dm.ToV2(coord) + 0.5,
                {0.5, 0.1},
                rotation = math.to_radians(DirToRot[dir]),
                color = {0, 0.1, 0.8, 0.5},
                pivot = {0, 0.5}
            )
        }
    }

    // Draw energy packets
    packetIt := dm.MakePoolIter(&gameState.energyPackets)
    for packet in dm.PoolIterate(&packetIt) {
        dm.DrawBlankSprite(packet.position, .4, EnergyColor[packet.energyType])
    }

    // Enemy
    enemyIt := dm.MakePoolIter(&gameState.enemies)
    for enemy in dm.PoolIterate(&enemyIt) {
        stats := Enemies[enemy.statsIdx]
        dm.DrawBlankSprite(enemy.position, .4, color = stats.tint)
    }


    enemyIt = dm.MakePoolIter(&gameState.enemies)
    for enemy in dm.PoolIterate(&enemyIt) {
        stats := Enemies[enemy.statsIdx]
        p := enemy.health / stats.maxHealth
        color := math.lerp(dm.RED, dm.GREEN, p)
        
        dm.DrawBlankSprite(enemy.position + {0, 0.6}, {1 * p, 0.09}, color = color)
    }

    // Player
    dm.DrawSprite(gameState.playerSprite, gameState.playerPosition)

    // path
    for i := 0; i < len(gameState.path) - 1; i += 1 {
        a := gameState.path[i]
        b := gameState.path[i + 1]

        dm.DrawLine(dm.renderCtx, dm.ToV2(a) + {0.5, 0.5}, dm.ToV2(b) + {0.5, 0.5}, false, dm.GREEN)
    }

    for k, path in gameState.pathsBetweenBuildings {
        for i := 0; i < len(path) - 1; i += 1 {
            a := path[i]
            b := path[i + 1]

            dm.DrawLine(dm.renderCtx, dm.ToV2(a) + {0.5, 0.5}, dm.ToV2(b) + {0.5, 0.5}, false, dm.RED)
        }
    }

    dm.UpdateAndDrawParticleSystem(&gameState.turretFireParticle)

    dm.DrawText(dm.renderCtx, "WIP version: 0.0.1 pre-pre-pre-pre-pre-alpha", dm.LoadDefaultFont(dm.renderCtx), {0, f32(dm.renderCtx.frameSize.y - 30)}, 20)
}
