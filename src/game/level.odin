package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"
import pq "core:container/priority_queue"

import "../ldtk"


Tile :: struct {
    worldPos: v2,
    sprite: dm.Sprite,

    building: BuildingHandle,

    hasWire: bool,

    type: TileType,
}

Level  :: struct {
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

        for layer in loadedLevel.layer_instances {
            yOffset := layer.c_height * layer.grid_size

            if layer.identifier == "Base" {
                tiles := layer.type == .Tiles ? layer.grid_tiles : layer.auto_layer_tiles
                level.grid = make([]Tile, layer.c_width * layer.c_height)

                for tile, i in tiles {
                    // posX := f32(tile.px.x) / f32(layer.grid_size) + 0.5
                    // posY := f32(-tile.px.y + yOffset) / f32(layer.grid_size) - 0.5

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
                        worldPos = v2{posX, posY}
                    }
                }
            }

            if layer.identifier == "TileTypes" {
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

            if layer.identifier == "Entities" {
                for entity in layer.entity_instances {
                    coord := iv2{i32(entity.grid.x), i32(entity.grid.y)}
                    coord.y = level.sizeY - coord.y - 1

                    switch entity.identifier {
                    case "StartPoint": level.startCoord = coord
                    case "EndPoint": level.endCoord = coord
                    }
                }
            }
        }
    }

    return
}

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

GetNeighbours :: proc(coord: iv2, allocator := context.allocator) -> []iv2 {
    ret := make([dynamic]iv2, 0, 8, allocator = allocator)

    for x := i32(-1); x <= i32(1); x += 1 {
        for y := i32(-1); y <= i32(1); y += 1 {
            n := coord + {x, y}
            if n == coord {
                continue
            }

            if(IsInsideGrid(n)) {
                append(&ret, n)
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
        definition = building,
        gridPos = gridPos,
        position = dm.ToV2(gridPos) + dm.ToV2(building.size) / 2,
    }

    // fmt.println(gridPos)

    handle := dm.AppendElement(&gameState.spawnedBuildings, toSpawn)

    // TODO: check for outside grid coords
    for y in 0..<toSpawn.size.y {
        for x in 0..<toSpawn.size.x {
            idx := CoordToIdx(gridPos + {x, y})
            gameState.level.grid[idx].building = handle
        }
    }
}


RemoveBuilding :: proc(building: BuildingHandle) {
    inst, ok := dm.GetElementPtr(gameState.spawnedBuildings, building)
    if ok == false {
        return
    }

    for y in 0..<inst.size.y {
        for x in 0..<inst.size.x {
            tile := GetTileAtCoord(inst.gridPos + {x, y})
            tile.building = {}
        }
    }

    dm.FreeSlot(gameState.spawnedBuildings, building)
    inst.handle = {}
}

CalculatePath :: proc(level: Level, start, goal: iv2) -> []iv2 {
    // openCoords := make([dynamic]iv2, 0, level.sizeX, allocator = context.temp_allocator)
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
                if tile.type != .WalkArea || tile.hasWire {
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