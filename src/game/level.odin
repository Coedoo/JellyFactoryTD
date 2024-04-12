package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

import "../ldtk"

Tile :: struct {
    worldPos: v2,
    sprite: dm.Sprite,

    building: BuildingHandle,
}

LoadGrid :: proc() {
    tilesHandle := dm.GetTextureAsset("tiles.png")
    // levelAsset := LevelAsset

    level := dm.GetAssetData("level1.ldtk")
    project, ok := ldtk.load_from_memory(level.fileData).?

    if ok == false {
        fmt.eprintln("Failed to load level file")
        return
    }

    for level in project.levels {
        levelPxSize := iv2{i32(level.px_width), i32(level.px_height)}
        levelSize := dm.ToV2(levelPxSize) / 32

        gameState.gridX = i32(levelSize.x)
        gameState.gridY = i32(levelSize.y)

        for layer in level.layer_instances {
            yOffset := layer.c_height * layer.grid_size

            if layer.identifier == "Base" {
                tiles := layer.type == .Tiles ? layer.grid_tiles : layer.auto_layer_tiles
                gameState.grid = make([]Tile, len(tiles))

                for tile, i in tiles {
                    posX := f32(tile.px.x) / f32(layer.grid_size) + 0.5
                    posY := f32(-tile.px.y + yOffset) / f32(layer.grid_size) - 0.5

                    sprite := dm.CreateSprite(
                        tilesHandle,
                        dm.RectInt{i32(tile.src.x), i32(tile.src.y), 32, 32}
                    )

                    gameState.grid[i] = Tile {
                        sprite = sprite,
                        worldPos = v2{posX, posY}
                    }
                }
            }
        }
    }
}

IsInsideGrid :: proc(coord: iv2) -> bool {
    return coord.x >= 0 && coord.x < gameState.gridX &&
           coord.y >= 0 && coord.y < gameState.gridY
}

CoordToIdx :: proc(coord: iv2) -> i32 {
    assert(IsInsideGrid(coord))
    return coord.y * gameState.gridX + coord.x
}

IsTileFree :: proc(coord: iv2) -> bool {
    idx := CoordToIdx(coord)
    return gameState.grid[idx].building == {}
}

GetTileOnWorldPos :: proc(pos: v2) -> ^Tile {
    x := i32(pos.x)
    y := i32(pos.y)

    return GetTileAtCoord({x, y})
}

GetTileAtCoord :: proc(coord: iv2) -> ^Tile {
    if IsInsideGrid(coord) {
        idx := CoordToIdx(coord)
        return &gameState.grid[idx]
    }

    return nil
}

////////////////////

CanBePlaced :: proc(building: Building, coord: iv2) -> bool {
    for y in 0..<building.size.y {
        for x in 0..<building.size.x {
            pos := coord + {x, y}
            
            if IsInsideGrid(pos) == false {
                return false
            }

            if IsTileFree(pos) == false {
                return false
            }
        }
    }

    return true
}

TryPlaceBuilding :: proc(buildingIdx: int, position: iv2) {
    building := Buildings[buildingIdx]

    if CanBePlaced(building, position) == false {
        return
    }

    toSpawn := BuildingInstance {
        definition = building,
        gridPos = position,
    }

    // fmt.println(position)

    handle := dm.AppendElement(&gameState.spawnedBuildings, toSpawn)

    // TODO: check for outside grid coords
    for y in 0..<toSpawn.size.y {
        for x in 0..<toSpawn.size.x {
            idx := CoordToIdx(position + {x, y})
            gameState.grid[idx].building = handle
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
    // for &b, i in gameState.spawnedBuildings.elements {
    //     if &b == building {
    //         unordered_remove(&gameState.spawnedBuildings, i)
    //         fmt.println("Removing building at index", i)
    //         break
    //     }
    // }

}