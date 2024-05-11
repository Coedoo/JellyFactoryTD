package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

import "../ldtk"

BuildingHandle :: dm.Handle

BuildingFlag :: enum {
    ProduceEnergy,
    RequireEnergy,
    Attack,
}

BuildignFlags :: distinct bit_set[BuildingFlag]

IOType :: enum {
    None,
    Input,
    Output,
}

BuildingIO :: struct {
    offset: iv2,
    type: IOType
}

Building :: struct {
    name: string,
    spriteName: string,
    spriteRect: dm.RectInt,

    flags: BuildignFlags,

    size: iv2,

    // Connections
    // inputsPos: []iv2,
    // outputsPos: []iv2,

    connectionsPos: []iv2,

    // Energy
    energyStorage: f32,
    energyProduction: f32,

    // Attack
    range: f32,
    energyRequired: f32,
    reloadTime: f32,
}

BuildingInstance :: struct {
    using definition: Building,
    handle: BuildingHandle,

    gridPos: iv2,
    position: v2,

    // energy
    currentEnergy: f32,

    // attack
    attackTimer: f32,

    connectedBuildings: [dynamic]BuildingHandle,
}


Buildings := [?]Building {
    {
        name = "Factory 1",
        spriteName = "buildings.png",
        spriteRect = {0, 0, 32, 32},

        size = {1, 1},

        flags = {.ProduceEnergy},

        energyStorage = 100,
        energyProduction = 25,

        // outputsPos = {{-1, 0}, {1, 0}, {0, 1}, {0, -1}}
        connectionsPos = {{-1, 0}, {1, 0}, {0, 1}, {0, -1}}
    },

    {
        name = "Turret 1",
        spriteName = "buildings.png",
        spriteRect = {32, 0, 32, 32},

        size = {1, 1},

        flags = {.Attack, .RequireEnergy},

        energyStorage = 100,
        // energyProduction = 25,

        range = 3,
        energyRequired = 10,
        reloadTime = 0.2,

        // inputsPos = {{1, 0}}
        connectionsPos = {{1, 0}}

    },
}

AddEnergy :: proc(building: ^BuildingInstance, value: f32) -> f32 {
    spaceLeft := building.energyStorage - building.currentEnergy
    clamped := clamp(value, 0, spaceLeft)

    building.currentEnergy += clamped
    return value - clamped
}

RemoveEnergy :: proc(building: ^BuildingInstance, value: f32) -> f32 {
    removed := min(value, building.currentEnergy)
    building.currentEnergy -= removed

    return removed
}

CheckBuildingConnection :: proc(startCoord: iv2) {
    queue := make([dynamic]iv2, 0, 16, allocator = context.temp_allocator)
    visited := make([dynamic]iv2, 0, 16, allocator = context.temp_allocator)
    buildingsInNetwork := make([dynamic]BuildingHandle, 0, 16, allocator = context.temp_allocator)

    append(&queue, startCoord)
    append(&visited, startCoord)

    for len(queue) > 0 {
        coord := pop(&queue)
        tile := GetTileAtCoord(coord)

        neighbours := GetNeighbourTiles(coord, context.temp_allocator)
        for neighbour in neighbours {
            delta := neighbour.gridPos - coord
            dir := VecToDir(delta)

            if (dir in tile.wireDir) &&
                slice.contains(visited[:], neighbour.gridPos) == false
            {
                append(&queue, neighbour.gridPos)
                append(&visited, coord)
            }


            if neighbour.building != {} &&
               slice.contains(buildingsInNetwork[:], neighbour.building) == false
            {
                append(&buildingsInNetwork, neighbour.building)
            }
        }
    }

    for handleA in buildingsInNetwork {
        building := dm.GetElementPtr(gameState.spawnedBuildings, handleA) or_continue
        clear(&building.connectedBuildings)

        for handleB in buildingsInNetwork {
            if handleA != handleB {
                append(&building.connectedBuildings, handleB)
            }
        }
    }
}