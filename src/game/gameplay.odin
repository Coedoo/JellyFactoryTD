package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"
import "core:mem"

BuildUpMode :: enum {
    None,
    Building,
    Pipe,
    Destroy,
}

GameplayUpdate :: proc() {
    cursorOverUI := dm.muiIsCursorOverUI(dm.input.mousePos)

    // Move Player
    moveX := dm.GetAxis(.A, .D)
    moveY := dm.GetAxis(.S, .W)

    moveVec := v2{
        moveX,
        moveY
    }

    if moveVec != {0, 0} {
        moveVec = glsl.normalize(moveVec)
        gameState.playerPosition += moveVec * PLAYER_SPEED * f32(dm.time.deltaTime)


        gameState.playerSprite.flipX = false
        gameState.playerSprite.flipY = false

        if moveX != 0 && moveY != 0 {
            if moveY  == -1 {
                gameState.playerSprite.texturePos.y = 192
            }
            else {
                gameState.playerSprite.texturePos.y = 256
            }
            gameState.playerSprite.flipX = moveX == -1 ? true : false
        }
        else if moveY == 1 {
            gameState.playerSprite.texturePos.y = 64
        }
        else if moveY == -1 {
            gameState.playerSprite.texturePos.y = 0
        }
        else if moveX != 0 {
            gameState.playerSprite.texturePos.y = 128
            gameState.playerSprite.flipX = moveX == -1 ? true : false
        }

        gameState.playerMoveParticles.position = gameState.playerPosition
        gameState.playerMoveParticles.emitRate = 30
    }
    else {
        gameState.playerMoveParticles.emitRate = 0
    }

    gameState.playerPosition.x = clamp(gameState.playerPosition.x, 0, f32(gameState.loadedLevel.sizeX))
    gameState.playerPosition.y = clamp(gameState.playerPosition.y, 0, f32(gameState.loadedLevel.sizeY))

    // Camera Control
    camAspect := dm.renderCtx.camera.aspect
    camHeight := dm.renderCtx.camera.orthoSize
    camWidth  := camAspect * camHeight

    levelSize := v2{
        f32(gameState.loadedLevel.sizeX),
        f32(gameState.loadedLevel.sizeY),
    }

    if gameState.buildUpMode == .None {
        scroll := dm.input.scroll if cursorOverUI == false else 0
        camHeight = camHeight - f32(scroll) * 0.3
        camWidth = camAspect * camHeight
    }

    camHeight = clamp(camHeight, 0, levelSize.x / 2)
    camWidth  = clamp(camWidth,  0, levelSize.y / 2)

    camSize := min(camHeight, camWidth / camAspect)
    dm.renderCtx.camera.orthoSize = camSize

    camPos := gameState.playerPosition
    camPos.x = clamp(camPos.x, camWidth,  levelSize.x - camWidth)
    camPos.y = clamp(camPos.y, camHeight, levelSize.y - camHeight)
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

            building.currentEnergy[building.producedEnergyType] += produced
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

            building.energyParticles.emitRate = allEnergy / buildingData.energyStorage * 20
            keys: dm.RandomColorKeys
            sum: f32

            idx := 1
            for energy, typeIdx in building.currentEnergy {
                if energy != 0 {
                    sum += energy

                    type := EnergyType(typeIdx)
                    keys.keys[idx] = {sum / allEnergy, EnergyColor[type]}

                    idx += 1
                }
            }
            keys.keysCount = idx

            slice.sort_by(
                keys.keys[0:idx], 
                proc(a, b: dm.ValueKey(dm.color)) -> bool { 
                    return a.time < b.time
                }
            )

            if sum == 0 {
                // keys = EnergyParticleSystem.color.(dm.ColorKeysOverLifetime)
            }
            else {
                building.energyParticles.startColor = keys
            }

            // for particle in building.energyParticles.particles {
            //     fmt.println(particle.color)
            // }

            // building.energyParticlesTimer -= dm.time.deltaTime
            // if building.energyParticlesTimer < 0 {
            //     building.energyParticlesTimer = 0.1

            //     for energy, i in building.currentEnergy {
            //         type := cast(EnergyType) i
            //         if type != .None {
            //             perc := energy / buildingData.energyStorage
            //             amount := int(math.round(perc * 5))
            //             dm.SpawnParticles(
            //                 &gameState.tileEnergyParticles[type],
            //                 amount,
            //                 building.position,
            //                 EnergyColor[type]
            //             )
            //         }
            //     }
            // }
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

                ordered_remove(&building.requestedEnergyQueue, 0)

                target, ok := dm.GetElementPtr(gameState.spawnedBuildings, request.to)
                if ok && canSpawn {
                    targetData := Buildings[target.dataIdx]

                    building.packetSpawnTimer = buildingData.packetSpawnInterval

                    pathKey := PathKey{
                        from = building.handle,
                        to   = target.handle,
                        }
                    path, pathExists := gameState.pathsBetweenBuildings[pathKey]

                    if pathExists {
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
            // enemy, ok := dm.GetElementPtr(gameState.enemies, building.targetEnemy)
            // if ok {
            //     delta := building.position - enemy.position
            //     building.turretAngle = math.atan2(delta.y, delta.x) + math.PI / 2
            // }
        }

        if .Attack in buildingData.flags {
            building.attackTimer -= f32(dm.time.deltaTime)
            building.fireTimer -= dm.time.deltaTime

            switch building.targetingMethod {
            case .KeepTarget:
                if building.targetEnemy == {} {
                    building.targetEnemy = FindClosestEnemy(building.position, buildingData.range)
                }

            case .Closest:
                building.targetEnemy = FindClosestEnemy(building.position, buildingData.range)

            case .LowestPathDist:
                enemies := FindEnemiesInRange(building.position, buildingData.range)
                minDist := max(f32)
                for &e in enemies {
                    dist := DistanceLeft(e)
                    if dist < minDist {
                        minDist = dist
                        building.targetEnemy = e.handle
                    }
                }
            }

            enemy, ok := dm.GetElementPtr(gameState.enemies, building.targetEnemy)
            if ok == false {
                building.targetEnemy = {}
                continue
            }

            if glsl.distance(building.position, enemy.position) > buildingData.range {
                building.targetEnemy = {}
                continue
            }

            // dm.DrawDebugLine(dm.renderCtx, enemy.position, building.position, false)


            currentEnergy := BuildingEnergy(building)
            if currentEnergy >= buildingData.energyRequired &&
               building.attackTimer <= 0
            {
                building.attackTimer = buildingData.reloadTime

                building.fireTimer = SHOT_VISUAL_TIMER
                building.firePosition = enemy.position
                // angle := building.turretAngle + math.PI / 2
                // delta := v2 {
                //     math.cos(angle),
                //     math.sin(angle),
                // }

                // dm.SpawnParticles(&gameState.turretFireParticle, 10, building.position + delta)

                usedEnergy := RemoveEnergyFromBuilding(building, buildingData.energyRequired)

                switch buildingData.attackType {
                case .Simple:
                    DamageEnemy(enemy, buildingData.damage, usedEnergy)

                case .Cannon:
                    enemies := FindEnemiesInRange(enemy.position, buildingData.attackRadius)
                    for e in enemies {
                        DamageEnemy(e, buildingData.damage, usedEnergy)
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
            series = gameState.loadedLevel.waves.waves[i],
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

        if spawnedCount >= len(gameState.loadedLevel.waves.waves[i]) {
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
    if gameState.buildUpMode == .Building {
        if dm.GetMouseButton(.Left) == .JustPressed &&
           cursorOverUI == false
        {
            idx := gameState.selectedBuildingIdx
            building := Buildings[idx]

            pos := MousePosGrid()

            if IsInDistance(gameState.playerPosition, pos) {
                if CanBePlaced(building, pos) {
                    if RemoveMoney(building.cost) {
                        TryPlaceBuilding(idx, pos)
                    }
                }
            }
        }
    }

    // temp UI
    if dm.muiBeginWindow(dm.mui, "GAME MENU", {200, 10, 210, 450}) {
        dm.muiLabel(dm.mui, gameState.selectedTile)
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


        dm.muiLabel(dm.mui, "Wave Idx:", gameState.currentWaveIdx, "/", len(gameState.loadedLevel.waves.waves))
        if dm.muiButton(dm.mui, "SpawnWave") {
            StartNextWave()
        }

        if dm.muiButton(dm.mui, "Reset level") {
            // name := gameState.level.name
            // OpenLevel(name)
        }

        dm.muiLabel(dm.mui, "LEVELS:")
        for l in gameState.levels {
            if dm.muiButton(dm.mui, l.name) {
                OpenLevelByName(l.name)
            }
        }

        dm.muiLabel(dm.mui, "MEMORY")
        dm.muiLabel(dm.mui, "\tLevel arena HWM:", gameState.levelArena.peak_used / mem.Kilobyte, "kb")
        dm.muiLabel(dm.mui, "\tLevel arena used:", gameState.levelArena.offset / mem.Kilobyte, "kb")


        dm.muiEndWindow(dm.mui)
    }

    tile := GetTileAtCoord(gameState.selectedTile)
    if tile != nil && (tile.building != {} || tile.pipeDir != {}) {
        building, buildingData := GetBuilding(tile.building)
        // dm.DrawDebugCircle(dm.renderCtx, building.position, buildingData.range, false, dm.RED)

        if dm.muiBeginWindow(dm.mui, "Selected Building", {600, 10, 140, 250}, {.NO_CLOSE}) {
            dm.muiLabel(dm.mui, tile.pipeDir)

            if dm.muiHeader(dm.mui, "Building") {
                if tile.building != {} {
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

    if dm.Panel("Main") {
        style := dm.uiCtx.panelStyle
        style.fontSize = 40
        dm.PushStyle(style)

        dm.UILabel("Wave: ", gameState.currentWaveIdx, '/', len(gameState.wavesState), sep = "")

        style.fontSize = 30
        dm.PushStyle(style)
        dm.UILabel("Enemies left:", dm.PoolLen(gameState.enemies))

        dm.PopStyle()
        dm.PopStyle()

        if dm.UIButton("NextWave") {
            StartNextWave()
        }
    }

    @static showBuildingPanel: bool
    if dm.UIButton("Build") {
        showBuildingPanel = !showBuildingPanel
    }

    if showBuildingPanel do if dm.Panel("Buildings") {

        for idx := 0; idx < len(Buildings); {
            dm.PushId(idx)
            dm.BeginLayout("BuildingsX", axis = .X)

            for _ in 0..<3 {
                b := Buildings[idx]
                tex := dm.GetTextureAsset(b.spriteName)

                if dm.ImageButton(tex, b.name, maybeSize = iv2{50, 50}, texSource = b.spriteRect) {
                    gameState.selectedBuildingIdx = idx
                    gameState.buildUpMode = .Building
                }

                idx += 1
                if idx >= len(Buildings) {
                    break
                }
            }

            dm.EndLayout()
            dm.PopId()
        }
    }

    @static amount := 5
    if dm.UIContainer("TEEEEEST", .MiddleCenter) {
        if dm.Panel("KLDFJLSK") {
            dm.Scroll("tiles scroll", {100, 300})
            {
                dm.UILabel("AAAAAAAAAAAAAAAAAAAAAAAAAAA")

                for i in 0..=amount {
                    dm.UILabel(fmt.tprint("Stuff", i))
                }

                if dm.UIButton("Add") do amount += 1
                if dm.UIButton("Remove") do amount -= 1
            }
            dm.EndScroll()
        }
    }
}

GameplayRender :: proc() {
    for &t in gameState.particlesTimers {
        t -= f32(dm.time.deltaTime)
    }

    // Level
    for tile, idx in gameState.loadedLevel.grid {
        sprite := dm.GetSprite(Tileset.atlas, tile.atlasPos)
        sprite.flipX = tile.tileFlip.x
        sprite.flipY = tile.tileFlip.y
        dm.DrawSprite(sprite, CoordToPos(tile.gridPos))

        if tile.energy != .None {
            if gameState.particlesTimers[tile.energy] < 0 {
                dm.SpawnParticles(&gameState.tileEnergyParticles[tile.energy], 1, CoordToPos(tile.gridPos))
            }
        }

    }

    for &t in gameState.particlesTimers {
        t -= f32(dm.time.deltaTime)
        if t < 0 {
            t = 0.3 + rand.float32_range(-0.1, 0.1)
        }
    }


    // Pipe
    for tile, idx in gameState.loadedLevel.grid {
        for dir in tile.pipeDir {
            dm.DrawRectPos(
                dm.renderCtx.whiteTexture,
                CoordToPos(tile.gridPos),
                size = v2{0.5, 0.1},
                rotation = math.to_radians(DirToRot[dir]),
                color = {0, 0.1, 0.8, 0.9},
                origin = {0, 0.5}
            )
        }
    }

    // Draw Buildings

    // shader := dm.GetAsset("Shaders/test.hlsl")
    // dm.PushShader(cast(dm.ShaderHandle) shader)
    for &building in gameState.spawnedBuildings.elements {
        // @TODO @CACHE
        buildingData := &Buildings[building.dataIdx]
        tex := dm.GetTextureAsset(buildingData.spriteName)
        sprite := dm.CreateSprite(tex, buildingData.spriteRect)
        sprite.scale = f32(buildingData.size.x)

        pos := building.position
        // color := GetEnergyColor(building.currentEnergy)

        // dm.SetShaderData(2, [4]f32{1, 0, 1, 1})
        dm.DrawSprite(sprite, pos)

        // energy Particles
        if .RequireEnergy in buildingData.flags {
            dm.UpdateAndDrawParticleSystem(&building.energyParticles)
        }

        // firing effect
        if building.fireTimer > 0 {
            delta := building.firePosition - building.position
            rayPos := building.position + delta / 2
            rot := math.atan2(delta.y, delta.x)

            p := building.fireTimer / SHOT_VISUAL_TIMER
            alpha := p

            dm.DrawRectBlank(rayPos, {glsl.length(delta), 0.08}, rotation = rot, color = {1, 1, 1, alpha})
        }

        // currentEnergy := BuildingEnergy(&building)
        // if buildingData.energyStorage != 0 {
        //     // @TODO this breaks batching
        //     dm.DrawWorldRect(
        //         dm.renderCtx.whiteTexture, 
        //         dm.ToV2(building.gridPos) + {f32(buildingData.size.x), f32(buildingData.size.y) / 2},
        //         {0.1, currentEnergy / buildingData.energyStorage}
        //     )
        // }

        // if .RotatingTurret in buildingData.flags {
        //     sprite := dm.CreateSprite(tex, buildingData.turretSpriteRect)
        //     sprite.origin = buildingData.turretSpriteOrigin
        //     sprite.scale = f32(buildingData.size.x)
            
        //     dm.DrawSprite(sprite, pos, rotation = building.turretAngle)
        // }

        // if dm.platform.debugState {
        //     if .Attack in buildingData.flags {
        //         dm.DrawCircle(dm.renderCtx, pos, buildingData.range, false)
        //     }
        // }
    }
    // dm.PopShader()

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
            dm.DrawRectPos(
                dm.renderCtx.whiteTexture,
                dm.ToV2(coord) + 0.5,
                size = v2{0.5, 0.1},
                rotation = math.to_radians(DirToRot[dir]),
                color = color,
                origin = {0, 0.5}
            )
        }
    }

    // Destroying
    if gameState.buildUpMode == .Destroy {
        if IsInDistance(gameState.playerPosition, MousePosGrid()) {
            tile := TileUnderCursor()
            if tile.building != {} || tile.pipeDir != nil {
                dm.DrawRectBlank(CoordToPos(tile.gridPos), 1, color = {1, 0, 0, 0.5})
            }
        }
    }

    // Draw energy packets
    packetIt := dm.MakePoolIter(&gameState.energyPackets)
    energyTex := dm.GetTextureAsset("Energy.png")
    for packet in dm.PoolIterate(&packetIt) {
        dm.DrawRect(energyTex, packet.position, 1, color = EnergyColor[packet.energyType])
    }

    // draw Enemy
    enemyIt := dm.MakePoolIter(&gameState.enemies)
    for enemy in dm.PoolIterate(&enemyIt) {
        stats := Enemies[enemy.statsIdx]
        dm.DrawRect(enemy.position, .4, color = stats.tint)
    }

    enemyIt = dm.MakePoolIter(&gameState.enemies)
    for enemy in dm.PoolIterate(&enemyIt) {
        stats := Enemies[enemy.statsIdx]
        p := enemy.health / stats.maxHealth
        color := math.lerp(dm.RED, dm.GREEN, p)
        
        dm.DrawRect(enemy.position + {0, 0.6}, {1 * p, 0.09}, color = color)

        if enemy.slowValue.timeLeft > 0 {
            dm.DrawRect(enemy.position + {0, -0.4}, {enemy.slowValue.timeLeft / 5, 0.09}, color = dm.CYAN)
        }

        if enemy.poisonValue.timeLeft > 0 {
            dm.DrawRect(enemy.position + {0, -0.5}, {enemy.poisonValue.timeLeft / 5, 0.09}, color = dm.GREEN)
        }
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

                    dm.DrawRectBlank(CoordToPos(coord), {1, 1}, color = color)
                }
            }
        }

        dm.DrawGrid()
    }

    // Player
    dm.UpdateAndDrawParticleSystem(&gameState.playerMoveParticles)
    dm.AnimateSprite(&gameState.playerSprite, f32(dm.time.gameTime), 0.1)
    // dm.DrawSprite(gameState.playerSprite, gameState.playerPosition)

    // path
    for i := 0; i < len(gameState.path) - 1; i += 1 {
        a := gameState.path[i]
        b := gameState.path[i + 1]

        posA := CoordToPos(a)
        posB := CoordToPos(b)
        dm.DrawDebugLine(dm.renderCtx, posA, posB, false, dm.BLUE)
        dm.DrawDebugCircle(dm.renderCtx, posA, 0.1, false, dm.BLUE)
    }

    // mouseGrid := MousePosGrid()
    // tiles: [dynamic]iv2
    // hit := IsEmptyLineBetweenCoords(gameState.selectedTile, mouseGrid, &tiles)
    // dm.DrawDebugLine(dm.renderCtx, CoordToPos(gameState.selectedTile), CoordToPos(mouseGrid), false)
    // for t in tiles {
    //     pos := CoordToPos(t)
    //     dm.DrawBlankSprite(pos, {1, 1}, {0, 1, 0, 0.4} if hit else {1, 0, 0, 0.4})
    // }

    if gameState.debugDrawPathsBetweenBuildings {
        for k, path in gameState.pathsBetweenBuildings {
            for i := 0; i < len(path) - 1; i += 1 {
                a := path[i]
                b := path[i + 1]

                dm.DrawDebugLine(dm.renderCtx, dm.ToV2(a) + {0.5, 0.5}, dm.ToV2(b) + {0.5, 0.5}, false, dm.RED)
            }
        }
    }

    dm.UpdateAndDrawParticleSystem(&gameState.turretFireParticle)
    for &system in gameState.tileEnergyParticles {
        dm.UpdateAndDrawParticleSystem(&system)
    }


    selectedTile := GetTileAtCoord(gameState.selectedTile)
    if selectedTile != nil {
        for waypoint in selectedTile.visibleWaypoints {
            dm.DrawDebugLine(dm.renderCtx, CoordToPos(gameState.selectedTile), CoordToPos(waypoint), false)
        }
    }

    if gameState.debugDrawPathGraph {
        for tile, idx in gameState.loadedLevel.grid {
            if tile.isCorner {
                dm.DrawRectBlank(CoordToPos(tile.gridPos), {1, 1}, color = {1, 0, 0, 0.8})
            }

            for nextT in tile.visibleWaypoints {
                dm.DrawDebugLine(dm.renderCtx, CoordToPos(tile.gridPos), CoordToPos(nextT), false)
            }
        }


        // selectedTile := GetTileAtCoord(gameState.selectedTile)
        // if selectedTile != nil {
        //     for waypoint in selectedTile.visibleWaypoints {
        //         dm.DrawDebugLine(dm.renderCtx, CoordToPos(gameState.selectedTile), CoordToPos(waypoint), false)
        //     }
        // }
    }


    if gameState.debugDrawGrid {
        dm.DrawGrid()
    }

    // dm.DrawText("WIP version: 0.0.1 pre-pre-pre-pre-pre-alpha", 
    //     {0, f32(dm.renderCtx.frameSize.y - 30)}, 
    //     font = dm.LoadDefaultFont(dm.renderCtx),
    //     20)
}