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

Building :: struct {
    name: string,
    spriteName: string,
    spriteRect: dm.RectInt,

    flags: BuildignFlags,

    size: iv2,

    // Connections
    inputsPos: []iv2,
    outputsPos: []iv2,

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
        energyProduction = 5,

        outputsPos = {{-1, 0}, {1, 0}, {0, 1}, {0, -1}}
    },

    {
        name = "Turret 1",
        spriteName = "buildings.png",
        spriteRect = {32, 0, 32, 32},

        size = {1, 1},

        flags = {.Attack},

        energyStorage = 100,
        energyProduction = 5,

        range = 3,
        energyRequired = 10,
        reloadTime = 0.2,

        inputsPos = {{1, 0}}

    },
}

CheckBuildingConnection :: proc(startCoord: iv2) {
    queue := make([dynamic]iv2, 0, 16, allocator = context.temp_allocator)
    visited := make([dynamic]iv2, 0, 16, allocator = context.temp_allocator)
    buildingsInNetwork := make([dynamic]BuildingHandle, 0, 16, allocator = context.temp_allocator)

    append(&queue, startCoord)
    append(&visited, startCoord)

    for len(queue) > 0 {
        coord := pop(&queue)

        neighbours := GetNeighbourTiles(coord, context.temp_allocator)
        for neighbour in neighbours {
            if neighbour.wireDir != nil &&
               slice.contains(visited[:], neighbour.gridPos) == false
            {
                append(&queue, neighbour.gridPos)
                append(&visited, coord)
            }

            if neighbour.building != {} && slice.contains(buildingsInNetwork[:], neighbour.building) == false  {
                append(&buildingsInNetwork, neighbour.building)
            }
        }
    }

    for handle in buildingsInNetwork {
        building := dm.GetElementPtr(gameState.spawnedBuildings, handle) or_continue

        if handle == building.handle || slice.contains(building.connectedBuildings[:], handle) {
            continue
        }

        append(&building.connectedBuildings, handle)
    }
}