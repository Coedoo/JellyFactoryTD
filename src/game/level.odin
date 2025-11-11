package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:mem"

import sa "core:container/small_array"
import pq "core:container/priority_queue"

TileFlag :: enum {
    Walkable,
    NonBuildable,
}

TileFlags :: distinct bit_set[TileFlag]

TileCategory :: enum {
    Other,
    Road,
    BuildSpace,
    Resources,
}

TileDefinition :: struct {
    name: string,
    category: TileCategory,

    atlasPos: iv2,
    flags: TileFlags,

    energy: EnergyType,
}

TileSet :: struct {
    atlas: dm.SpriteAtlas,
    tiles: []TileDefinition,
}

Tile :: struct {
    defIndex: int,
    using def: ^TileDefinition `json:"-"`,

    tileFlip: [2]bool,

    gridPos: iv2,

    building: BuildingHandle `json:"-"`,
    pipeDir: DirectionSet `json:"-"`,

    isCorner: bool `json:"-"`,
    visibleWaypoints: []iv2 `json:"-"`,

    activeInConnectionTest: bool `json:"-"`,
}

TileStartingValues :: struct {
    hasBuilding: bool,
    buildingIdx: int,
    pipeDir: DirectionSet,
}

Level  :: struct {
    name: string,
    sizeX, sizeY: i32,

    grid: []Tile,
    startingState: []TileStartingValues,

    startCoord: iv2,
    endCoord: iv2,

    waves: sa.Small_Array(MAX_WAVES, Wave),
}

// @NOTE: Must be the same values as LDTK
// @TODO: can I import it as well?
// TileType :: enum {
//     None,
//     // Walls = 1,
//     BuildArea = 2,
//     WalkArea = 3,
//     Edge = 4,
//     BlueEnergy = 5,
//     RedEnergy = 6,
//     GreenEnergy = 7,
//     CyanEnergy = 8,
// }

// TileTypeColor := #sparse [TileType]dm.color {
//     .None = {0, 0, 0, 1},
//     // .Walls = {0.73, 0.21, 0.4, 0.5},
//     .BuildArea   = ({0, 153, 219, 128} / 255.0),
//     .WalkArea    = ({234, 212, 170, 128} / 255.0),
//     .Edge        = {0.2, 0.2, 0.2, 0.5},
//     .BlueEnergy  = {0, 0, 1, 0.5},
//     .RedEnergy   = {1, 0, 0, 0.5},
//     .GreenEnergy = {0, 1, 0, 0.5},
//     .CyanEnergy  = {0, 1, 1, 0.5},
// }

// EnergyTileTypes :: []TileType{.BlueEnergy, .RedEnergy, .GreenEnergy, .CyanEnergy}

/////

InitNewLevel :: proc(level: ^Level, width, height: int) {
    // width := state.newLevelWidth
    // height := state.newLevelHeight

    level.sizeX = i32(width)
    level.sizeY = i32(height)

    level.grid = make([]Tile, width * height)
    for &tile, i in level.grid {
        x := i % width
        y := i / width

        tile.gridPos = {i32(x), i32(y)}
        tile.def = &Tileset.tiles[0]
    }

    // atlas := dm.GetTextureAsset("kenney_tilemap.png")
    // level.tileset = {
    //     texAssetPath = "kenney_tilemap.png",
    //     texture  = atlas,
    //     cellSize = {16, 16},
    //     spacing = {1, 1}
    // }

    // state.editedLevel.tileset = state.tileset
}

LoadLevels :: proc() -> (levels: []Level) {
    return nil
}

OpenLevelByName :: proc(name: string) {
    for &l in gameState.levels {
        if l.name == name {
            // gameState.loadedLevel = &l
            OpenLevel(&l)
            break
        }
    }

    fmt.println("Can't Open level with name:", name);
}

OpenLevel :: proc(level: ^Level) {
    CloseCurrentLevel()

    gameState.loadedLevel = level

    mem.zero_item(&gameState.levelState)
    free_all(gameState.levelAllocator)
    gameState.levelArena.peak_used = 0

    context.allocator = gameState.levelAllocator

    dm.InitResourcePool(&gameState.spawnedBuildings, 128)
    dm.InitResourcePool(&gameState.enemies, 1024)
    dm.InitResourcePool(&gameState.energyPackets, 1024)

    pathMem := make([]byte, PATH_MEMORY)
    mem.arena_init(&gameState.pathArena, pathMem)
    gameState.pathAllocator = mem.arena_allocator(&gameState.pathArena)

    for &tile, i in level.grid {
        tile.def = &Tileset.tiles[tile.defIndex]
    }

    //@TODO: it would be better to start test level in this case
    // assert(gameState.level != nil, fmt.tprintf("Failed to start level of name:", name))

    // waves: LevelWaves
    // for w in Waves {
    //     if w.levelName == name {
    //         waves = w
    //         break
    //     }
    // }

    // if waves.waves == nil {
    //     fmt.eprintln("Can't find waves list for level ", name)
    // }

    // gameState.levelWaves = waves
    // level.waves = Waves[0]
    // gameState.wavesState = make([]WaveState, len(level.waves.waves), allocator = gameState.levelAllocator)
    // for &s, i in gameState.wavesState {
    //     s.seriesStates = make([]SeriesState, len(level.waves.waves[i]), allocator = gameState.levelAllocator)
    // }

    gameState.money = START_MONEY
    gameState.hp    = START_HP

    gameState.playerPosition = dm.ToV2(iv2{gameState.loadedLevel.sizeX, gameState.loadedLevel.sizeY}) / 2

    // @NOTE: I'm doing this in two passes so TryPlaceBuilding already have
    // pipes to create paths between buildings
    // for &tile, i in gameState.loadedLevel.grid {
    //     if gameState.loadedLevel.startingState[i].pipeDir != nil {
    //         tile.pipeDir = gameState.loadedLevel.startingState[i].pipeDir
    //     }
    //     tile.isCorner = false
    // }

    // for &tile, i in gameState.loadedLevel.grid {
    //     if gameState.loadedLevel.startingState[i].hasBuilding {
    //         TryPlaceBuilding(gameState.loadedLevel.startingState[i].buildingIdx, tile.gridPos)
    //     }
    // }

    RefreshVisibilityGraph()
    gameState.path = CalculatePathWithCornerTiles(
        gameState.loadedLevel.startCoord,
        gameState.loadedLevel.endCoord,
        allocator = gameState.pathAllocator
    )

    // @TODO: this will probably need other place
    // Also I don't think I have to completely destroy particles
    // but that's TBD
    gameState.turretFireParticle = dm.DefaultParticleSystem
    gameState.turretFireParticle.maxParticles = 100
    gameState.turretFireParticle.texture = dm.renderCtx.whiteTexture
    gameState.turretFireParticle.lifetime = dm.RandomFloat{0.1, 0.2}
    gameState.turretFireParticle.startColor = dm.color{0, 1, 1, 1}
    gameState.turretFireParticle.startSize = dm.RandomFloat{0.1, 0.3}

    dm.InitParticleSystem(&gameState.turretFireParticle)
}

RefreshVisibilityGraph :: proc() {

    // Find corners
    @static
    cornerPatterns := [4][9]int{
        {1, 1, 0, 1, 0, 0, 0, 0, 0},
        {0, 1, 1, 0, 0, 1, 0, 0, 0},
        {0, 0, 0, 1, 0, 0, 1, 1, 0},
        {0, 0, 0, 0, 0, 1, 0, 1, 1},
    }

    @static
    cornerDirections := [4]iv2 {
        { -1, -1},
        {  1, -1},
        { -1,  1},
        {  1,  1},
    }

    // @TODO: optimisation
    for &tile in gameState.loadedLevel.grid {
        tile.isCorner = false
    }

    cornerTiles := make([dynamic]^Tile, allocator = context.temp_allocator)
    append(&cornerTiles, GetTileAtCoord(gameState.loadedLevel.startCoord))
    for &tile in gameState.loadedLevel.grid {
        // tile.isCorner = false

        foundPatterns := [4]bool{true, true, true, true}
        for pattern, patternIdx in cornerPatterns {
            if foundPatterns[patternIdx] == false {
                continue
            }

            for patternElement, index in pattern {
                offsetX := index % 3 - 1
                offsetY := index / 3 - 1

                if offsetX == 0 && offsetY == 0 {
                    continue
                }

                neighbor := tile.gridPos + {i32(offsetX), i32(offsetY)}
                neighborTile := GetTileAtCoord(neighbor)
                if neighborTile != nil {
                    found := true
                    if patternElement == 1 {
                        // @REWRITE:
                        found = .Walkable in neighborTile.flags && 
                                neighborTile.building == {} &&
                                (.Walkable not_in tile.flags ||
                                  tile.building != {})

                        // __|__|__
                        // __|__|__
                        //   |  |  
                    }
                    // found ||= patternElement == 0 && tile.type == .BuildArea

                    if found == false {
                        foundPatterns[patternIdx] = false
                    }
                }
            }
        }

        for found, patternIdx in foundPatterns {
            if found {
                // tile.isCorner = true
                // break
                offset := cornerDirections[patternIdx]
                cornerTile := GetTileAtCoord(tile.gridPos + offset)
                if cornerTile != nil {
                    cornerTile.isCorner = true
                    append(&cornerTiles, cornerTile)
                    // break
                }
            }
        }
    }
    append(&cornerTiles, GetTileAtCoord(gameState.loadedLevel.endCoord))

    CreateVisiblityGraph(cornerTiles[:])
}

CreateVisiblityGraph :: proc(cornerTiles: []^Tile) {
    visibleTiles := make([dynamic]iv2, allocator = context.temp_allocator)
    for tile in cornerTiles {
        clear(&visibleTiles)
        for otherTile in cornerTiles {
            if tile == otherTile {
                continue
            }

            if IsEmptyLineBetweenCoords(tile.gridPos, otherTile.gridPos) {
                append(&visibleTiles, otherTile.gridPos)
            }
        }

        tile.visibleWaypoints = make([]iv2, len(visibleTiles), gameState.pathAllocator)
        copy(tile.visibleWaypoints, visibleTiles[:])
    }
}

CloseCurrentLevel :: proc() {
    // if gameState.level == nil {
    //     return
    // }

    // mem.zero_item(&gameState.levelState)
    // free_all(gameState.levelAllocator)

    // for &tile in gameState.level.grid {
    //     tile.building = {}
    //     tile.pipeDir = nil
    // }

    // gameState.level = nil
}


///////////

IsInsideGrid :: proc {
    IsInsideGridLoadedLevel,
    IsInsideGridLevel,
}

IsInsideGridLoadedLevel :: proc(coord: iv2) -> bool {
    return coord.x >= 0 && coord.x < gameState.loadedLevel.sizeX &&
           coord.y >= 0 && coord.y < gameState.loadedLevel.sizeY
}

IsInsideGridLevel :: proc(level: ^Level, coord: iv2) -> bool {
    return coord.x >= 0 && coord.x < level.sizeX &&
           coord.y >= 0 && coord.y < level.sizeY
}

CoordToIdx :: proc {
    CoordToIdxLoadedLevel,
    CoordToIdxLevel,
}

CoordToIdxLoadedLevel :: proc(coord: iv2) -> i32 {
    assert(IsInsideGrid(coord))
    return coord.y * gameState.loadedLevel.sizeX + coord.x
}

CoordToIdxLevel :: proc(level: ^Level, coord: iv2) -> i32 {
    assert(IsInsideGrid(coord))
    return coord.y * level.sizeX + coord.x
}

WorldPosToCoord :: proc(pos: v2) -> iv2 {
    x := i32(pos.x)
    y := i32(pos.y)

    return {x, y}
}

IsTileFree :: proc {
    IsTileFreeLoadedLevel,
    IsTileFreeLevel,
}

IsTileFreeLoadedLevel :: proc(coord: iv2) -> bool {
    if len(gameState.loadedLevel.grid) == 0 {
        return false
    }

    idx := CoordToIdx(coord)
    return gameState.loadedLevel.grid[idx].building == {}
}


IsTileFreeLevel :: proc(level: ^Level, coord: iv2) -> bool {
    if len(level.grid) == 0 {
        return false
    }

    idx := CoordToIdx(coord)
    return level.grid[idx].building == {}
}

GetTileOnWorldPos :: proc(pos: v2) -> ^Tile {
    x := i32(pos.x)
    y := i32(pos.y)

    return GetTileAtCoord({x, y})
}

GetTileAtCoord :: proc {
    GetTileAtCoordLoadedLevel,
    GetTileAtCoordLevel,
}

GetTileAtCoordLoadedLevel :: proc(coord: iv2) -> ^Tile {
    if IsInsideGrid(coord) {
        idx := CoordToIdx(coord)
        return &gameState.loadedLevel.grid[idx]
    }

    return nil
}

GetTileAtCoordLevel :: proc(level: ^Level, coord: iv2) -> ^Tile {
    if IsInsideGrid(level, coord) {
        idx := CoordToIdx(level, coord)
        return &level.grid[idx]
    }

    return nil
}

TileUnderCursor :: proc {
    TileUnderCursorLoadedLevel,
    TileUnderCursorLevel,
}

TileUnderCursorLoadedLevel :: proc() -> ^Tile {
    coord := MousePosGrid()
    return GetTileAtCoord(coord)
}

TileUnderCursorLevel :: proc(level: ^Level) -> ^Tile {
    coord := MousePosGrid()
    return GetTileAtCoord(level, coord)
}

GetNeighbourCoords :: proc(coord: iv2, allocator := context.allocator) -> []iv2 {
    ret := make([dynamic]iv2, 0, 4, allocator = allocator)

    for x := i32(-1); x <= i32(1); x += 1 {
        for y := i32(-1); y <= i32(1); y += 1 {
            n := coord + {x, y}
            if (n.x != coord.x &&
                n.y != coord.y) ||
                n == coord
            {
                continue
            }


            if IsInsideGrid(n) {
                append(&ret, n)
            }
        }
    }

    return ret[:]
}

GetNeighbourTiles :: proc(coord: iv2, allocator := context.allocator) -> []^Tile {
    ret := make([dynamic]^Tile, 0, 4, allocator = allocator)

    for x := i32(-1); x <= i32(1); x += 1 {
        for y := i32(-1); y <= i32(1); y += 1 {
            n := coord + {x, y}
            if (n.x != coord.x &&
                n.y != coord.y) ||
               n == coord
            {
                continue
            }

            if(IsInsideGrid(n)) {
                append(&ret, GetTileAtCoord(n))
            }
        }
    }

    return ret[:]
}

GetNeighbourTilesLevel :: proc(level: ^Level, coord: iv2, allocator := context.allocator) -> []^Tile {
    ret := make([dynamic]^Tile, 0, 4, allocator = allocator)

    for x := i32(-1); x <= i32(1); x += 1 {
        for y := i32(-1); y <= i32(1); y += 1 {
            n := coord + {x, y}
            if (n.x != coord.x &&
                n.y != coord.y) ||
               n == coord
            {
                continue
            }

            if(IsInsideGrid(level, n)) {
                append(&ret, GetTileAtCoord(level, n))
            }
        }
    }

    return ret[:]
}

GetFloodFilledTiles :: proc(level: ^Level, coord: iv2, allocator := context.allocator) -> []^Tile {
    queue := make([dynamic]iv2, 0, 16, allocator = context.temp_allocator)

    result := make([dynamic]^Tile, 0, 16, allocator = allocator)

    firstTile := GetTileAtCoord(level, coord)

    append(&queue, coord)
    append(&result, firstTile)

    for len(queue) > 0 {
        tileCoord := pop(&queue)

        neighbours := GetNeighbourTilesLevel(level, tileCoord, context.temp_allocator)
        for neighbour in neighbours {

            if neighbour.defIndex == firstTile.defIndex && slice.contains(result[:], neighbour) == false
            {
                append(&queue, neighbour.gridPos)
                append(&result, neighbour)
            }
        }
    }

    return result[:]
}


////////////////////

CanBePlaced :: proc(building: Building, coord: iv2) -> bool {
    for y in 0..<building.size.y {
        for x in 0..<building.size.x {
            pos := coord + {x, y}

            if IsInsideGrid(pos) == false {
                return false
            }

            // if card(building.restrictedTiles) != 0 {
            //     tile := GetTileAtCoord(pos)

            //     found := false
            //     for restrictedTile in building.restrictedTiles {
            //         if tile.type == restrictedTile {
            //             found = true
            //             break
            //         }
            //     }

            //     if found == false {
            //         return false
            //     }
            // }

            if IsTileFree(pos) == false {
                return false
            }
        }
    }

    return true
}

TryPlaceBuilding :: proc(buildingIdx: int, gridPos: iv2) -> bool {
    building := Buildings[buildingIdx]
    if CanBePlaced(building, gridPos) == false {
        return false
    }


    // @Hack: activeInConnectionTest
    for y in 0..<building.size.y {
        for x in 0..<building.size.x {
            tile := GetTileAtCoord(gridPos + {x, y})
            tile.activeInConnectionTest = true
        }
    }

    testPath := CalculatePath (
        gameState.loadedLevel.startCoord,
        gameState.loadedLevel.endCoord,
        TestConnectionPredicate,
        context.temp_allocator
    )

    for y in 0..<building.size.y {
        for x in 0..<building.size.x {
            tile := GetTileAtCoord(gridPos + {x, y})
            tile.activeInConnectionTest = false
        }
    }

    // fmt.println(testPath)

    if testPath == nil {
        return false
    }

    PlaceBuilding(buildingIdx, gridPos)
    return true
}

PlaceBuilding :: proc(buildingIdx: int, gridPos: iv2) {
    building := Buildings[buildingIdx]
    toSpawn := BuildingInstance {
        dataIdx = buildingIdx,
        gridPos = gridPos,
        position = dm.ToV2(gridPos) + dm.ToV2(building.size) / 2,
    }

    buildingTile := GetTileAtCoord(gridPos)

    if .RequireEnergy in building.flags {
        toSpawn.energyParticles = EnergyParticleSystem
        toSpawn.energyParticles.position = toSpawn.position
        dm.InitParticleSystem(&toSpawn.energyParticles)
    }

    if .SendsEnergy in building.flags {
        toSpawn.requestedEnergyQueue = make([dynamic]EnergyRequest, 0, 64, gameState.levelAllocator)
    }

    // @TODO: handle different building sizes
    if .ProduceEnergy in building.flags {
        toSpawn.producedEnergyType = buildingTile.energy
    }

    handle := dm.AppendElement(&gameState.spawnedBuildings, toSpawn)

    // TODO: check for outside grid coords
    for y in 0..<building.size.y {
        for x in 0..<building.size.x {
            idx := CoordToIdx(gridPos + {x, y})
            gameState.loadedLevel.grid[idx].building = handle
            gameState.loadedLevel.grid[idx].pipeDir = {}
        }
    }

    // Find and place pipes
    startX := gridPos.x - 1
    endX   := gridPos.x + building.size.x

    startY := gridPos.y - 1
    endY   := gridPos.y + building.size.y

    SetPipe :: proc(coord, neighbor: iv2, targetDir: Direction) {
        buildingTile := GetTileAtCoord(coord)

        if IsInsideGrid(neighbor) {
            tile := GetTileAtCoord(neighbor)
            if ReverseDir[targetDir] in tile.pipeDir {
                buildingTile.pipeDir += { targetDir }
            }
        }
    }

    for x in startX + 1 ..= endX - 1 {
        SetPipe({x, startY + 1}, {x, startY}, .South)
    }

    for x in startX + 1 ..= endX - 1 {
        SetPipe({x, endY - 1}, {x, endY}, .North)
    }

    for y in startY + 1 ..= endY - 1 {
        SetPipe({startX + 1, y}, {startX, y}, .West)
    }

    for y in startY + 1 ..= endY - 1 {
        SetPipe({endX - 1, y}, {endX, y}, .East)
    }

    CheckBuildingConnection(gridPos)
    RefreshVisibilityGraph()

    gameState.path = CalculatePathWithCornerTiles(
        gameState.loadedLevel.startCoord,
        gameState.loadedLevel.endCoord,
        allocator = gameState.pathAllocator
    )

}


RemoveBuilding :: proc(building: BuildingHandle) {
    inst, ok := dm.GetElementPtr(gameState.spawnedBuildings, building)
    if ok == false {
        return
    }

    #reverse for connectedHandle in inst.energyTargets {
        other := dm.GetElementPtr(gameState.spawnedBuildings, connectedHandle) or_continue
        idx := slice.linear_search(other.energySources[:], building) or_continue

        // @NOTE: @TODO: this will change update order and potentially
        // game outcome. Is that ok?
        unordered_remove(&other.energySources, idx)
    }

    for key, path in gameState.pathsBetweenBuildings {
        if key.from == building || key.to == building {
            it := dm.MakePoolIterReverse(&gameState.energyPackets)
            for packet in dm.PoolIterate(&it) {
                if packet.pathKey == key {
                    dm.FreeSlot(&gameState.energyPackets, packet.handle)
                }
            }

            delete_key(&gameState.pathsBetweenBuildings, key)
        }
    }

    buildingData := &Buildings[inst.dataIdx]
    for y in 0..<buildingData.size.y {
        for x in 0..<buildingData.size.x {
            tile := GetTileAtCoord(inst.gridPos + {x, y})
            tile.building = {}
            tile.pipeDir = {}
        }
    }

    dm.FreeSlot(&gameState.spawnedBuildings, building)
}

TileTraversalPredicate :: #type proc(currentTile: Tile, neighbor: Tile, goal: iv2) -> bool

TestConnectionPredicate :: proc(currentTile: Tile, neighbor: Tile, goal: iv2) -> bool {
    return neighbor.gridPos == goal || 
        (
            .Walkable in neighbor.flags && 
            neighbor.building == {} &&
            neighbor.activeInConnectionTest == false
        )
}

WalkablePredicate :: proc(currentTile: Tile, neighbor: Tile, goal: iv2) -> bool {
    return neighbor.gridPos == goal || (.Walkable in neighbor.flags && neighbor.building == {})
}

PipePredicate :: proc(currentTile: Tile, neighbor: Tile, goal: iv2) -> bool {
    delta :=  neighbor.gridPos - currentTile.gridPos
    dir := VecToDir(delta)
    reverse := ReverseDir[dir]

    return (dir in currentTile.pipeDir && 
            reverse in neighbor.pipeDir) && 
           (neighbor.building == {} ||
            neighbor.gridPos == goal ||
            HasFlagHandle(neighbor.building, .EnergyModifier))
}

CalculatePath :: proc(start, goal: iv2, traversalPredicate: TileTraversalPredicate, allocator := context.allocator) -> []iv2 {
    openCoords: pq.Priority_Queue(iv2)

    // @TODO: I can probably make gScore and fScore as 2d array so 
    // there is no need for maps
    cameFrom := make(map[iv2]iv2, allocator = context.temp_allocator)
    gScore   := make(map[iv2]f32, allocator = context.temp_allocator)
    fScore   := make(map[iv2]f32, allocator = context.temp_allocator)

    Heuristic :: proc(a, b: iv2) -> f32 {
        return glsl.distance(dm.ToV2(a), dm.ToV2(b))
    }

    Less :: proc(a, b: iv2) -> bool {
        scoreMap := cast(^map[iv2]f32) context.user_ptr
        aScore := scoreMap[a] or_else max(f32)
        bScore := scoreMap[b] or_else max(f32)

        return aScore < bScore
    }

    context.user_ptr = &fScore
    pq.init(&openCoords, Less, pq.default_swap_proc(iv2))

    pq.push(&openCoords, start)

    gScore[start] = 0
    fScore[start] = Heuristic(start, goal)

    for pq.len(openCoords) > 0 {
        current := pq.peek(openCoords)
        if current == goal {
            ret := make([dynamic]iv2, allocator)
            append(&ret, current)

            for (current in cameFrom) {
                current = cameFrom[current]
                inject_at(&ret, 0, current)
            }

            return ret[:]
        }

        currentTile := GetTileAtCoord(current)

        pq.pop(&openCoords)
        neighboursCoords := GetNeighbourCoords(current, allocator = context.temp_allocator)
        for neighborCoord in neighboursCoords {
            neighbourTile := GetTileAtCoord(neighborCoord)

            if traversalPredicate(currentTile^, neighbourTile^, goal) == false {
                continue
            }

            // @NOTE: I can make it depend on the edge on the tilemap
            // weight := glsl.distance(dm.ToV2(current), dm.ToV2(neighborCoord))
            newScore := gScore[current] + 1
            oldScore := gScore[neighborCoord] or_else max(f32)
            if newScore < oldScore {
                cameFrom[neighborCoord] = current
                gScore[neighborCoord] = newScore
                fScore[neighborCoord] = newScore + Heuristic(neighborCoord, goal)
                if slice.contains(openCoords.queue[:], neighborCoord) == false {
                    pq.push(&openCoords, neighborCoord)
                }
            }
        }
    }

    return nil
}

CalculatePathWithCornerTiles :: proc(start, goal: iv2, allocator := context.allocator) -> []iv2 {
    openCoords: pq.Priority_Queue(iv2)

    // @TODO: I can probably make gScore and fScore as 2d array so 
    // there is no need for maps
    cameFrom := make(map[iv2]iv2, allocator = context.temp_allocator)
    gScore   := make(map[iv2]f32, allocator = context.temp_allocator)
    fScore   := make(map[iv2]f32, allocator = context.temp_allocator)

    Heuristic :: proc(a, b: iv2) -> f32 {
        return glsl.distance(dm.ToV2(a), dm.ToV2(b))
    }

    Less :: proc(a, b: iv2) -> bool {
        scoreMap := cast(^map[iv2]f32) context.user_ptr
        aScore := scoreMap[a] or_else max(f32)
        bScore := scoreMap[b] or_else max(f32)

        return aScore < bScore
    }

    context.user_ptr = &fScore
    pq.init(&openCoords, Less, pq.default_swap_proc(iv2))

    pq.push(&openCoords, start)

    gScore[start] = 0
    fScore[start] = Heuristic(start, goal)

    for pq.len(openCoords) > 0 {
        current := pq.peek(openCoords)
        if current == goal {
            ret := make([dynamic]iv2, allocator)
            append(&ret, current)

            for (current in cameFrom) {
                current = cameFrom[current]
                inject_at(&ret, 0, current)
            }

            return ret[:]
        }

        currentTile := GetTileAtCoord(current)

        pq.pop(&openCoords)
        // neighboursCoords := GetNeighbourCoords(current, allocator = context.temp_allocator)
        for neighborCoord in currentTile.visibleWaypoints {
            neighbourTile := GetTileAtCoord(neighborCoord)

            // if traversalPredicate(currentTile^, neighbourTile^, goal) == false {
            //     continue
            // }

            // @NOTE: I can make it depend on the edge on the tilemap
            weight := glsl.distance(dm.ToV2(current), dm.ToV2(neighborCoord))
            // weight *= weight
            newScore := gScore[current] + weight
            oldScore := gScore[neighborCoord] or_else max(f32)
            if newScore < oldScore {
                cameFrom[neighborCoord] = current
                gScore[neighborCoord] = newScore
                fScore[neighborCoord] = newScore + Heuristic(neighborCoord, goal)
                if slice.contains(openCoords.queue[:], neighborCoord) == false {
                    pq.push(&openCoords, neighborCoord)
                }
            }
        }
    }

    return nil
}

IsEmptyLineBetweenCoords :: proc(coordA, coordB: iv2, checkedTiles: ^[dynamic]iv2 = nil) -> bool {
    // Use line drawing algorithm to chceck if there
    // is a straight line between coords that 
    // doesn't contain any non-wolkable tiles

    // http://playtechs.blogspot.com/2007/03/raytracing-on-grid.html
    // @NOTE: the article mentions that the algorithm might move in different
    // path, when start and end points are swapped. I'm not sure if that's 
    // an actual issue

    x0 := coordA.x
    y0 := coordA.y
    x1 := coordB.x
    y1 := coordB.y

    dx := abs(x1 - x0)
    dy := abs(y1 - y0)

    n :=  dx + dy + 1

    sx: i32 = x0 < x1 ? 1 : -1
    sy: i32 = y0 < y1 ? 1 : -1

    error := dx - dy
    dx *= 2
    dy *= 2

    clear(checkedTiles)
    for ; n > 0; n -= 1 {
        tile := GetTileAtCoord({x0, y0})
        if(checkedTiles != nil) {
            append(checkedTiles, tile.gridPos)
        }

        if tile.gridPos != coordA &&
           tile.gridPos != coordB &&
          (.Walkable not_in tile.flags ||
            tile.building != {})
        {
            return false
        }

        if error > 0 {
            x0 = x0 + sx
            error = error - dy
        }
        else {
            y0 = y0 + sy
            error = error + dx
        }
    }

    return true
}

// SimplifyPath :: proc(path: []iv2, allocator := context.allocator) -> []iv2 {
//     newPath := make([dynamic]iv2, 0, len(path), allocator = context.temp_allocator)
//     waypoints := make([dynamic]iv2, 0, len(path), allocator = context.temp_allocator)

//     append(&waypoints, path[0])
//     for i in 1..<len(path) {
//         coord := path[i]
//         tile := GetTileAtCoord(coord)

//         if tile.isCorner {
//             append(&waypoints, coord)
//         }

//         // for x in -1..=1 {
//         //     for y in -1..=1 {
//         //         // if x == 0 || y == 0 {
//         //         //     continue
//         //         // }

//         //         neighbor := GetTileAtCoord(coord + {i32(x), i32(y)})
//         //         if neighbor != nil && neighbor.isCorner {
//         //             append(&waypoints, coord)
//         //             break
//         //         }
//         //     }
//         // }
//     }
//     append(&waypoints, path[len(path) - 1])

//     wIdx := 0
//     for {
//         append(&newPath, waypoints[wIdx])
        
//         if wIdx >= len(waypoints) - 1 {
//             break
//         }

//         nextWaypointIdx := 0
//         for nextIdx in (wIdx + 1) ..< len(waypoints) {
//             if IsEmptyLineBetweenCoords(waypoints[wIdx], waypoints[nextIdx]) {
//                 nextWaypointIdx = nextIdx
//             }
//         }

//         if nextWaypointIdx == 0 {
//             break
//         }

//         wIdx = nextWaypointIdx
//     }
//     append(&newPath, path[len(path) - 1])

//     // newPath = waypoints

//     ret := make([]iv2, len(newPath), allocator = allocator)
//     copy(ret, newPath[:])

//     return ret
// }