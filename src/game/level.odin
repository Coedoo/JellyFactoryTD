package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:mem"
import pq "core:container/priority_queue"

import "../ldtk"


Tile :: struct {
    gridPos: iv2,
    worldPos: v2,
    sprite: dm.Sprite,

    building: BuildingHandle,

    // hasWire: bool,
    wireDir: DirectionSet,

    type: TileType,
}

Level  :: struct {
    name: string,
    grid: []Tile,
    sizeX, sizeY: i32,

    startCoord: iv2,
    endCoord: iv2,
}

// @NOTE: Must be the same values as LDTK
// @TODO: can I import it as well?
TileType :: enum {
    None,
    Walls = 1,
    BuildArea = 2,
    WalkArea = 3,
    Edge = 4,
}

TileTypeColor := [TileType]dm.color {
    .None = {0, 0, 0, 1},
    .Walls = {0.73, 0.21, 0.4, 0.5},
    .BuildArea = ({0, 153, 219, 128} / 255.0),
    .WalkArea = ({234, 212, 170, 128} / 255.0),
    .Edge = {0.2, 0.2, 0.2, 0.5},
}

/////

LoadLevels :: proc() -> (levels: []Level) {
    tilesHandle := dm.GetTextureAsset("kenney_tilemap.png")
    // levelAsset := LevelAsset

    ldtkFile := dm.GetAssetData("level1.ldtk")
    project, ok := ldtk.load_from_memory(ldtkFile.fileData).?

    if ok == false {
        fmt.eprintln("Failed to load level file")
        return
    }

    levels = make([]Level, len(project.levels))

    // @TODO: it's kinda error prone
    PixelsPerTile :: 16

    for loadedLevel, i in project.levels {
        levelPxSize := iv2{i32(loadedLevel.px_width), i32(loadedLevel.px_height)}
        levelSize := dm.ToV2(levelPxSize) / PixelsPerTile

        level := &levels[i]
        level.sizeX = i32(levelSize.x)
        level.sizeY = i32(levelSize.y)

        level.name = strings.clone(loadedLevel.identifier)

        for layer in loadedLevel.layer_instances {
            yOffset := layer.c_height * layer.grid_size

            if layer.identifier == "Base" {
                tiles := layer.type == .Tiles ? layer.grid_tiles : layer.auto_layer_tiles
                level.grid = make([]Tile, layer.c_width * layer.c_height)

                for tile, i in tiles {
                    sprite := dm.CreateSprite(
                        tilesHandle,
                        dm.RectInt{i32(tile.src.x), i32(tile.src.y), PixelsPerTile, PixelsPerTile}
                    )

                    coord := tile.px / layer.grid_size
                    // reverse the axis because LDTK Y axis goes down
                    coord.y = int(level.sizeY) - coord.y - 1

                    idx := coord.y * int(level.sizeX) + coord.x

                    posX := f32(coord.x) + 0.5
                    posY := f32(coord.y) + 0.5

                    level.grid[idx] = Tile {
                        sprite = sprite,
                        gridPos = iv2{i32(coord.x), i32(coord.y)},
                        worldPos = v2{posX, posY},
                        type = cast(TileType) layer.int_grid_csv[i]
                    }
                }

                // Setup tile's types
                for type, i in layer.int_grid_csv {
                    coord := iv2{
                        i32(i) % level.sizeX,
                        i32(i) / level.sizeX,
                    }

                    coord.y = level.sizeY - coord.y - 1
                    idx := coord.y * level.sizeX + coord.x

                    level.grid[idx].type = cast(TileType) type
                }
            }
            else if layer.identifier == "Entities" {
                for entity in layer.entity_instances {
                    coord := iv2{i32(entity.grid.x), i32(entity.grid.y)}
                    coord.y = level.sizeY - coord.y - 1

                    switch entity.identifier {
                    case "StartPoint": level.startCoord = coord
                    case "EndPoint": level.endCoord = coord
                    }
                }
            }
            else {
                fmt.eprintln("Unhandled level layer:", layer.identifier)
            }
        }
    }

    return
}


OpenLevel :: proc(name: string) {
    CloseCurrentLevel()

    mem.zero_item(&gameState.levelState)
    free_all(gameState.levelAllocator)

    context.allocator = gameState.levelAllocator

    dm.InitResourcePool(&gameState.spawnedBuildings, 128)
    dm.InitResourcePool(&gameState.enemies, 128)

    gameState.level = nil
    for &l in gameState.levels {
        if l.name == name {
            gameState.level = &l
            break;
        }
    }

    //@TODO: it would be better to start test level in this case
    assert(gameState.level != nil, fmt.tprintf("Failed to start level of name:", name))

    // @TODO: is dererferencing a pointer a copy?
    gameState.path = CalculatePath(gameState.level^, gameState.level.startCoord, gameState.level.endCoord)

    waves: LevelWaves
    for w in Waves {
        if w.levelName == name {
            waves = w
            break
        }
    }

    if waves.waves == nil {
        fmt.eprintln("Can't find waves list for level ", name)
    }

    gameState.levelWaves = waves
    gameState.wavesState = make([]WaveState, len(waves.waves), allocator = gameState.levelAllocator)
    for &s, i in gameState.wavesState {
        s.seriesStates = make([]SeriesState, len(waves.waves[i]), allocator = gameState.levelAllocator)
    }

    gameState.money = START_MONEY
    gameState.hp    = START_HP

    gameState.playerPosition = dm.ToV2(iv2{gameState.level.sizeX, gameState.level.sizeY}) / 2

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

CloseCurrentLevel :: proc() {
    if gameState.level == nil {
        return
    }

    mem.zero_item(&gameState.levelState)
    free_all(gameState.levelAllocator)

    for &tile in gameState.level.grid {
        tile.building = {}
        tile.wireDir = nil
    }

    gameState.level = nil
}


///////////

IsInsideGrid :: proc(coord: iv2) -> bool {
    return coord.x >= 0 && coord.x < gameState.level.sizeX &&
           coord.y >= 0 && coord.y < gameState.level.sizeY
}

CoordToIdx :: proc(coord: iv2) -> i32 {
    assert(IsInsideGrid(coord))
    return coord.y * gameState.level.sizeX + coord.x
}

IsTileFree :: proc(coord: iv2) -> bool {
    idx := CoordToIdx(coord)
    return gameState.level.grid[idx].building == {}
}

GetTileOnWorldPos :: proc(pos: v2) -> ^Tile {
    x := i32(pos.x)
    y := i32(pos.y)

    return GetTileAtCoord({x, y})
}

GetTileAtCoord :: proc(coord: iv2) -> ^Tile {
    if IsInsideGrid(coord) {
        idx := CoordToIdx(coord)
        return &gameState.level.grid[idx]
    }

    return nil
}

TileUnderCursor :: proc() -> ^Tile {
    coord := MousePosGrid()
    return GetTileAtCoord(coord)
}

GetNeighbours :: proc(coord: iv2, allocator := context.allocator) -> []iv2 {
    ret := make([dynamic]iv2, 0, 8, allocator = allocator)

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
                append(&ret, n)
            }
        }
    }

    return ret[:]
}

GetNeighbourTiles :: proc(coord: iv2, allocator := context.allocator) -> []^Tile {
    ret := make([dynamic]^Tile, 0, 8, allocator = allocator)

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

////////////////////

CanBePlaced :: proc(building: Building, coord: iv2) -> bool {
    for y in 0..<building.size.y {
        for x in 0..<building.size.x {
            pos := coord + {x, y}

            if IsInsideGrid(pos) == false {
                return false
            }

            tile := GetTileAtCoord(pos)
            if tile.type != .BuildArea {
                return false
            }

            if IsTileFree(pos) == false {
                return false
            }
        }
    }

    return true
}

TryPlaceBuilding :: proc(buildingIdx: int, gridPos: iv2) {
    building := Buildings[buildingIdx]

    if CanBePlaced(building, gridPos) == false {
        return
    }

    toSpawn := BuildingInstance {
        dataIdx = buildingIdx,
        gridPos = gridPos,
        position = dm.ToV2(gridPos) + dm.ToV2(building.size) / 2,
    }

    handle := dm.AppendElement(&gameState.spawnedBuildings, toSpawn)
    buildingTile := GetTileAtCoord(gridPos)

    // TODO: check for outside grid coords
    for y in 0..<building.size.y {
        for x in 0..<building.size.x {
            idx := CoordToIdx(gridPos + {x, y})
            gameState.level.grid[idx].building = handle
        }
    }

    buildingTile.wireDir = building.connections
    CheckBuildingConnection(gridPos)
}


RemoveBuilding :: proc(building: BuildingHandle) {
    inst, ok := dm.GetElementPtr(gameState.spawnedBuildings, building)
    if ok == false {
        return
    }

    for connectedHandle in inst.connectedBuildings {
        other := dm.GetElementPtr(gameState.spawnedBuildings, connectedHandle) or_continue
        idx := slice.linear_search(other.connectedBuildings[:], building) or_continue

        // @NOTE: @TODO: this will change update order and potentially
        // game outcome. Is that ok?
        unordered_remove(&other.connectedBuildings, idx)
    }

    buildingData := &Buildings[inst.dataIdx]
    for y in 0..<buildingData.size.y {
        for x in 0..<buildingData.size.x {
            tile := GetTileAtCoord(inst.gridPos + {x, y})
            tile.building = {}
        }
    }

    dm.FreeSlot(gameState.spawnedBuildings, building)
    inst.handle = {}
}

CalculatePath :: proc(level: Level, start, goal: iv2) -> []iv2 {
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
            ret := make([dynamic]iv2)
            append(&ret, current)

            for (current in cameFrom) {
                current = cameFrom[current]
                inject_at(&ret, 0, current)
            }

            return ret[:]
        }

        pq.pop(&openCoords)
        neighbours := GetNeighbours(current, allocator = context.temp_allocator)
        for n in neighbours {
            tile := GetTileAtCoord(n)

            if n != goal {
                if tile.type != .WalkArea {
                    continue
                }
            }

            // @NOTE: I can make it depend on the edge on the tilemap
            weight := glsl.distance(dm.ToV2(current), dm.ToV2(n))
            newScore := gScore[current] + weight
            oldScore := gScore[n] or_else max(f32)
            if newScore < oldScore {
                cameFrom[n] = current
                gScore[n] = newScore
                fScore[n] = newScore + Heuristic(n, goal)
                if slice.contains(openCoords.queue[:], n) == false {
                    pq.push(&openCoords, n)
                }
            }
        }
    }

    return nil
}