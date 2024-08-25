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


BuildUpMode :: enum {
    None,
    Building,
    Pipe,
    Destroy,
}


GameState :: struct {
    levelArena: mem.Arena,
    levelAllocator: mem.Allocator,

    levels: []Level,
    level: ^Level, // currentLevel

    using levelState: struct {
        spawnedBuildings: dm.ResourcePool(BuildingInstance, BuildingHandle),
        enemies: dm.ResourcePool(EnemyInstance, EnemyHandle),
        energyPackets: dm.ResourcePool(EnergyPacket, EnergyPacketHandle),

        money: int,
        hp: int,

        playerPosition: v2,

        path: []iv2,

        selectedTile: iv2,

        buildUpMode: BuildUpMode,
        selectedBuildingIdx: int,
        buildingPipeDir: DirectionSet,

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
    // dm.RegisterAsset("testTex.png", dm.TextureAssetDescriptor{})

    dm.RegisterAsset("level1.ldtk", dm.RawFileAssetDescriptor{})
    dm.RegisterAsset("kenney_tilemap.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("buildings.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("turret_test_4.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("Energy.png", dm.TextureAssetDescriptor{})

    dm.RegisterAsset("ship.png", dm.TextureAssetDescriptor{})

    dm.platform.SetWindowSize(1200, 900)
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

    if gameState.buildUpMode == .None {
        scroll := dm.input.scroll if cursorOverUI == false else 0
        camHeight = camHeight - f32(scroll) * 0.3
        camWidth = camAspect * camHeight
    }

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

        if .RequireEnergy in buildingData.flags {

            allEnergy := BuildingEnergy(building)
            // the loop here is weird because I want to start
            // the iteration from next unused energy source
            // to prevent situations where building is
            // supplied energy from just one source
            // which happened to be updated first

            requestedSourcesEnergy: [EnergyType]f32
            for sourceHandle in building.energySources {
                source := dm.GetElementPtr(gameState.spawnedBuildings, sourceHandle) or_continue

                for request in source.requestedEnergyQueue {
                    if request.to == building.handle {
                        requestedSourcesEnergy[request.type] += request.energy
                    }
                }
            }

            iter := dm.MakePoolIter(&gameState.energyPackets)
            for packet in dm.PoolIterate(&iter) {
                if packet.pathKey.to == building.handle {
                    requestedSourcesEnergy[packet.energyType] += packet.energy
                }
            }

            sources: for i := 0; i < len(building.energySources); i += 1 {

                idx := (building.lastUsedSourceIdx + i + 1) % len(building.energySources)
                sourceHandle := building.energySources[idx]
                source := dm.GetElementPtr(gameState.spawnedBuildings, sourceHandle) or_continue
                sourceData := Buildings[source.dataIdx]

                eType: EnergyType
                maxDiff: f32
                neededEnergy: f32

                for current, i in building.currentEnergy {
                    type := cast(EnergyType) i
                    energy := (
                        building.requiredEnergyFractions[type]
                        - requestedSourcesEnergy[type]
                        - building.currentEnergy[type]
                    )
                    energy = min(energy, sourceData.packetSize)

                    diff := source.currentEnergy[type] - energy

                    if energy > 0 &&
                       source.currentEnergy[type] > 0 &&
                        diff >= maxDiff
                    {
                        maxDiff = diff
                        eType = type
                        neededEnergy = energy
                    }
                }

                if neededEnergy <= 0 {
                    continue
                }

                for request in source.requestedEnergyQueue {
                    if request.to == building.handle {
                        continue sources
                    }
                }

                balanceType := (int(buildingData.balanceType) >= int(sourceData.balanceType) ?
                                buildingData.balanceType :
                                sourceData.balanceType)

                if balanceType == .Balanced {
                    if source.currentEnergy[eType] <= building.currentEnergy[eType] - neededEnergy {
                        continue
                    }
                }

                append(&source.requestedEnergyQueue, EnergyRequest{
                    to = building.handle,
                    energy = neededEnergy,
                    type = eType,
                })
                building.lastUsedSourceIdx = idx
            }
        }

        if .SendsEnergy in buildingData.flags {
            building.packetSpawnTimer -= f32(dm.time.deltaTime)
            canSpawn := building.packetSpawnTimer <= 0 &&
                        len(building.requestedEnergyQueue) > 0

            if  canSpawn {
                building.packetSpawnTimer = building.packetSpawnTimer

                request := building.requestedEnergyQueue[0]
                if building.currentEnergy[request.type] < request.energy {
                    continue
                }

                target, ok := dm.GetElementPtr(gameState.spawnedBuildings, request.to)
                targetData := Buildings[target.dataIdx]

                if canSpawn {
                    ordered_remove(&building.requestedEnergyQueue, 0)

                    building.packetSpawnTimer = buildingData.packetSpawnInterval

                    pathKey := PathKey{
                        from = building.handle,
                        to   = target.handle,
                        }
                    path, ok := gameState.pathsBetweenBuildings[pathKey]

                    if ok {
                        packet := dm.CreateElement(&gameState.energyPackets)

                        packet.path = path
                        packet.position = CoordToPos(packet.path[0])
                        packet.speed = 6
                        packet.energyType = request.type
                        packet.energy = request.energy
                        packet.pathKey = pathKey

                        building.currentEnergy[request.type] -= request.energy
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
    packetIt := dm.MakePoolIterReverse(&gameState.energyPackets)
    for packet in dm.PoolIterate(&packetIt) {
        UpdateFollower(packet, packet.speed)
        if packet.finishedPath {
            building, ok := dm.GetElementPtr(gameState.spawnedBuildings, packet.pathKey.to)
            if ok {
                building.currentEnergy[packet.energyType] += packet.energy
            }

            dm.FreeSlot(&gameState.energyPackets, packet.handle)
        }
        else if packet.enteredNewSegment {
            tile := GetTileAtCoord(packet.path[packet.nextPointIdx - 1])
            if tile.building != {} {
                inst, data := GetBuilding(tile.building)
                if .EnergyModifier in data.flags {
                    switch modifier in data.energyModifier {
                    case SpeedUpModifier:
                        packet.energy *= (1 - modifier.costPercent)
                        packet.speed *= modifier.multiplier

                    case ChangeColorModifier: 
                        packet.energy *= (1 - modifier.costPercent)
                        packet.energyType = modifier.targetType
                    }
                }
            }
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

    // Destroy structres
    if gameState.buildUpMode == .Destroy &&
       dm.GetMouseButton(.Left) == .JustPressed &&
       cursorOverUI == false
    {
        tile := TileUnderCursor()
        if tile.building != {} {
            RemoveBuilding(tile.building)
        }
        else if tile.pipeDir != {} {
            connectedBuildings := GetConnectedBuildings(tile.gridPos, allocator = context.temp_allocator)

            for dir in tile.pipeDir {
                neighborCoord := tile.gridPos + DirToVec[dir]
                neighbor := GetTileAtCoord(neighborCoord)
                if neighbor.building != {} {
                    neighbor.pipeDir -= { ReverseDir[dir] }
                }
            }

            tile.pipeDir = nil

            for handleA in connectedBuildings {
                buildingA := dm.GetElementPtr(gameState.spawnedBuildings, handleA) or_continue

                #reverse for handleB, i in buildingA.energyTargets {
                    buildingB := dm.GetElementPtr(gameState.spawnedBuildings, handleB) or_continue

                    key := PathKey{buildingA.handle, buildingB.handle}
                    oldPath := gameState.pathsBetweenBuildings[key] or_continue
                    newPath := CalculatePath(buildingA.gridPos, buildingB.gridPos, PipePredicate)

                    if PathsEqual(oldPath, newPath) {
                        continue
                    }

                    delete(oldPath)

                    if newPath != nil {
                        gameState.pathsBetweenBuildings[key] = newPath
                    }
                    else {
                        delete_key(&gameState.pathsBetweenBuildings, key)

                        unordered_remove(&buildingA.energyTargets, i)

                        if idx, found := slice.linear_search(buildingB.energySources[:], handleA); found {
                            unordered_remove(&buildingB.energySources, idx)
                        }
                    }

                    // Delete packets on old path
                    it := dm.MakePoolIterReverse(&gameState.energyPackets)
                    for packet in dm.PoolIterate(&it) {
                        if packet.pathKey == key {
                            dm.FreeSlot(&gameState.energyPackets, packet.handle)
                        }
                    }
                }
            }
        }
    }

    if dm.GetMouseButton(.Right) == .JustPressed &&
       cursorOverUI == false
    {
        gameState.buildUpMode = .None
    }

    // Pipe
    if gameState.buildUpMode == .Pipe &&
       cursorOverUI == false
    {
        @static prevCoord: iv2

        leftBtn := dm.GetMouseButton(.Left)
        if leftBtn == .Down  {
            coord := MousePosGrid()
            if IsInDistance(gameState.playerPosition, coord) {
                tile := GetTileAtCoord(coord)

                canPlace :=  (prevCoord != coord || tile.pipeDir != gameState.buildingPipeDir)
                canPlace &&= tile.pipeDir != gameState.buildingPipeDir
                canPlace &&= tile.building == {}

                if canPlace {
                    tile.pipeDir = gameState.buildingPipeDir
                    for dir in gameState.buildingPipeDir {
                        neighborCoord := coord + DirToVec[dir]
                        neighbor := GetTileAtCoord(neighborCoord)
                        if neighbor.building != {} {
                            neighbor.pipeDir += { ReverseDir[dir] }
                        }
                    }

                    CheckBuildingConnection(tile.gridPos)

                    prevCoord = coord
                }
            }
        }

        if dm.input.scroll != 0 {
            dirSet := NextDir if dm.input.scroll < 0 else PrevDir
            newSet: DirectionSet
            for dir in gameState.buildingPipeDir {
                newSet += { dirSet[dir] }
            }
            gameState.buildingPipeDir = newSet
        }
    }

    // Highlight Building 
    if gameState.buildUpMode == .None && cursorOverUI == false {
        if dm.GetMouseButton(.Left) == .JustPressed {
            coord := MousePosGrid()
            gameState.selectedTile = coord
        }
    }

    // Building
    if gameState.buildUpMode == .Building
    {
        // if dm.input.scroll != 0 {
        //     dirSet := NextDir if dm.input.scroll < 0 else PrevDir
        //     gameState.buildedStructureRotation = dirSet[gameState.buildedStructureRotation]
        // }

        if dm.GetMouseButton(.Left) == .JustPressed &&
           cursorOverUI == false
        {
            idx := gameState.selectedBuildingIdx
            building := Buildings[idx]

            pos := MousePosGrid()

            if IsInDistance(gameState.playerPosition, pos) {
                if CanBePlaced(building, pos) {
                    if RemoveMoney(building.cost) {
                        PlaceBuilding(idx, pos)
                    }
                }
            }
        }
    }

    // temp UI
    if dm.muiBeginWindow(dm.mui, "GAME MENU", {10, 10, 110, 450}) {
        dm.muiLabel(dm.mui, "Money:", gameState.money)
        dm.muiLabel(dm.mui, "HP:", gameState.hp)

        for b, idx in Buildings {
            if dm.muiButton(dm.mui, b.name) {
                gameState.selectedBuildingIdx = idx
                gameState.buildUpMode = .Building
            }
        }

        dm.muiLabel(dm.mui, "Pipes:")
        if dm.muiButton(dm.mui, "Stright") {
            gameState.buildUpMode = .Pipe
            gameState.buildingPipeDir = DirVertical
        }
        if dm.muiButton(dm.mui, "Angled") {
            gameState.buildUpMode = .Pipe
            gameState.buildingPipeDir = DirNE
        }
        if dm.muiButton(dm.mui, "Triple") {
            gameState.buildUpMode = .Pipe
            gameState.buildingPipeDir = {.South, .North, .East}
        }
        if dm.muiButton(dm.mui, "Quad") {
            gameState.buildUpMode = .Pipe
            gameState.buildingPipeDir = DirSplitter
        }

        dm.muiLabel(dm.mui)
        if dm.muiButton(dm.mui, "Destroy") {
            gameState.buildUpMode = .Destroy
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

    tile := GetTileAtCoord(gameState.selectedTile)
    if tile.building != {} || tile.pipeDir != {} {
        if dm.muiBeginWindow(dm.mui, "Selected Building", {600, 10, 140, 250}, {.NO_CLOSE}) {
            dm.muiLabel(dm.mui, tile.pipeDir)

            if dm.muiHeader(dm.mui, "Building") {
                if tile.building != {} {
                    building, ok := dm.GetElementPtr(gameState.spawnedBuildings, tile.building)
                    if ok {
                        data := &Buildings[building.dataIdx]
                        dm.muiLabel(dm.mui, "Name:", data.name)
                        dm.muiLabel(dm.mui, building.handle)
                        dm.muiLabel(dm.mui, "Pos:", building.gridPos)
                        // dm.muiLabel(dm.mui, "requestedEnergy:", building.requestedEnergy)

                        if .RequireEnergy in data.flags {
                            dm.muiLabel(dm.mui, "Fractions:", building.requiredEnergyFractions)
                        }

                        if .SendsEnergy in data.flags {
                            dm.muiLabel(dm.mui, "Spawn timer:", building.packetSpawnTimer)
                        }

                        dm.muiLabel(dm.mui, "Energy:", BuildingEnergy(building), "/", data.energyStorage)
                        if dm.muiHeader(dm.mui, "Energy") {
                            for eType in EnergyType {
                                dm.muiLayoutRow(dm.mui, {40, -1}, 13)
                                dm.muiLabel(dm.mui, eType)
                                dm.muiSlider(dm.mui, &building.currentEnergy[eType], 0, data.energyStorage)
                            }
                        }

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

                        if .SendsEnergy in data.flags &&
                            dm.muiHeader(dm.mui, "Request Queue")
                        {
                            for b in building.requestedEnergyQueue {
                                dm.muiLabel(dm.mui, b)
                            }
                        }
                    }
                }
            }

            dm.muiEndWindow(dm.mui)
        }
    }

    if gameState.buildUpMode != .None {
        size := iv2{
            100, 60
        }

        pos := iv2{
            dm.renderCtx.frameSize.x / 2 - size.x / 2,
            dm.renderCtx.frameSize.y - 100,
        }

        if dm.muiBeginWindow(dm.mui, "Current Mode", {pos.x, pos.y, size.x, size.y}, 
            {.NO_CLOSE, .NO_RESIZE})
        {
            label := gameState.buildUpMode == .Building ? "Building" :
                     gameState.buildUpMode == .Pipe     ? "Pipe" :
                     gameState.buildUpMode == .Destroy  ? "Destroy" :
                                                          "UNKNOWN MODE"

            dm.muiLabel(dm.mui, label)

            dm.muiEndWindow(dm.mui)
        }
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
        if DEBUG_TILE_OVERLAY {
            dm.DrawBlankSprite(tile.worldPos, {1, 1}, TileTypeColor[tile.type])
        }
    }


    // Pipe
    for tile, idx in gameState.level.grid {
        for dir in tile.pipeDir {
            dm.DrawWorldRect(
                dm.renderCtx.whiteTexture,
                tile.worldPos,
                {0.5, 0.1},
                rotation = math.to_radians(DirToRot[dir]),
                color = {0, 0.1, 0.8, 0.9},
                pivot = {0, 0.5}
            )
        }
    }

    // Buildings
    for &building in gameState.spawnedBuildings.elements {
        // @TODO @CACHE
        buildingData := &Buildings[building.dataIdx]
        tex := dm.GetTextureAsset(buildingData.spriteName)
        sprite := dm.CreateSprite(tex, buildingData.spriteRect)
        sprite.scale = f32(buildingData.size.x)

        pos := building.position
        dm.DrawSprite(sprite, pos)

        currentEnergy := BuildingEnergy(&building)
        if buildingData.energyStorage != 0 {
            // @TODO this breaks batching
            dm.DrawWorldRect(
                dm.renderCtx.whiteTexture, 
                dm.ToV2(building.gridPos) + {f32(buildingData.size.x), f32(buildingData.size.y) / 2},
                {0.1, currentEnergy / buildingData.energyStorage}
            )
        }

        if .RotatingTurret in buildingData.flags {
            sprite := dm.CreateSprite(tex, buildingData.turretSpriteRect)
            sprite.origin = buildingData.turretSpriteOrigin
            sprite.scale = f32(buildingData.size.x)
            
            dm.DrawSprite(sprite, pos, rotation = building.turretAngle)
        }

        if dm.platform.debugState {
            if .Attack in buildingData.flags {
                dm.DrawCircle(dm.renderCtx, pos, buildingData.range, false)
            }
        }
    }

    // Selected building
    if gameState.buildUpMode == .Building {
        gridPos := MousePosGrid()

        building := Buildings[gameState.selectedBuildingIdx]

        // @TODO @CACHE
        tex := dm.GetTextureAsset(building.spriteName)
        sprite := dm.CreateSprite(tex, building.spriteRect)

        color := dm.GREEN
        if CanBePlaced(building, gridPos) == false {
            color = dm.RED
        }

        // @TODO: make this a function
        pos := MousePosGrid()
        playerPos := WorldPosToCoord(gameState.playerPosition)

        delta := pos - playerPos

        if delta.x * delta.x + delta.y * delta.y > BUILDING_DISTANCE * BUILDING_DISTANCE {
            color = dm.RED
        }

        dm.DrawSprite(
            sprite, 
            dm.ToV2(gridPos) + dm.ToV2(building.size) / 2, 
            color = color, 
        )
    }

    // Draw Building Pipe
    if gameState.buildUpMode == .Pipe {
        coord := MousePosGrid()

        color: dm.color = (IsInDistance(gameState.playerPosition, coord) ?
                           {0, 0.1, 0.8, 0.5} :
                           {0.8, 0.1, 0, 0.5})

        for dir in gameState.buildingPipeDir {
            dm.DrawWorldRect(
                dm.renderCtx.whiteTexture,
                dm.ToV2(coord) + 0.5,
                {0.5, 0.1},
                rotation = math.to_radians(DirToRot[dir]),
                color = color,
                pivot = {0, 0.5}
            )
        }
    }

    // Destroying
    if gameState.buildUpMode == .Destroy {
        if IsInDistance(gameState.playerPosition, MousePosGrid()) {
            tile := TileUnderCursor()
            if tile.building != {} || tile.pipeDir != nil {
                dm.DrawBlankSprite(tile.worldPos, 1, {1, 0, 0, 0.5})
            }
        }
    }

    // Draw energy packets
    packetIt := dm.MakePoolIter(&gameState.energyPackets)
    energyTex := dm.GetTextureAsset("Energy.png")
    for packet in dm.PoolIterate(&packetIt) {
        dm.DrawWorldRect(energyTex, packet.position, 1, color = EnergyColor[packet.energyType])
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

    // Building Range
    if gameState.buildUpMode != .None {

        playerCoord := WorldPosToCoord(gameState.playerPosition)
        building := Buildings[gameState.selectedBuildingIdx]

        for y in -BUILDING_DISTANCE..=BUILDING_DISTANCE {
            for x in -BUILDING_DISTANCE..=BUILDING_DISTANCE {

                coord := playerCoord + iv2{i32(x), i32(y)}
                if IsInsideGrid(coord) &&
                    IsInDistance(gameState.playerPosition, coord)
                {

                    color: dm.color
                    switch gameState.buildUpMode {
                    case .Building: 
                        color = (CanBePlaced(building, coord) ?
                                           {0, 1, 0, 0.2} :
                                           {1, 0, 0, 0.2})

                    case .Pipe: 
                        tile := GetTileAtCoord(coord)
                        color = (tile.building == {} ?
                                           {0, 0, 1, 0.2} :
                                           {1, 0, 0, 0.2})

                    case .Destroy:
                        color = {1, 0, 0, 0.2}

                    case .None:
                    }

                    dm.DrawBlankSprite(CoordToPos(coord), {1, 1}, color)
                }
            }
        }

        dm.DrawGrid()
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
