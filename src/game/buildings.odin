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

    // Visuals
    RotatingTurret,
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

AttackType :: enum {
    None,
    Simple,
    Cannon,
}

Building :: struct {
    name: string,
    spriteName: string,
    spriteRect: dm.RectInt,
    turretSpriteRect: dm.RectInt,
    turretSpriteOrigin: v2,

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
    damage: f32,
    energyRequired: f32,
    reloadTime: f32,
}

BuildingInstance :: struct {
    // using definition: Building,
    handle: BuildingHandle,
    dataIdx: int,

    gridPos: iv2,
    position: v2,

    // energy
    currentEnergy: f32,

    // attack
    attackTimer: f32,
    targetEnemy: EnemyHandle,

    turretAngle: f32,
    targetTurretAngle: f32,

    connectedBuildings: [dynamic]BuildingHandle,
}

// RotatingTurretSpriteRects := [8]dm.RectInt{
//     {2 * 32, 1 * 32, 32, 32},
//     {2 * 32, 0 * 32, 32, 32},
//     {1 * 32, 0 * 32, 32, 32},
//     {0 * 32, 0 * 32, 32, 32},
//     {0 * 32, 1 * 32, 32, 32},
//     {0 * 32, 2 * 32, 32, 32},
//     {1 * 32, 2 * 32, 32, 32},
//     {2 * 32, 2 * 32, 32, 32},
// }

TurretSprite :: struct {
    rect: dm.RectInt,
    flipX, flipY: bool,
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
        spriteName = "turret_test_3.png",
        spriteRect = {0, 32, 32, 32},
        turretSpriteRect = {32, 0, 32, 64},
        turretSpriteOrigin = {0.5, 0.75},

        size = {1, 1},

        flags = {.Attack, .RequireEnergy, .RotatingTurret},

        energyStorage = 100,
        // energyProduction = 25,

        range = 4,
        energyRequired = 20,
        reloadTime = 0.2,
        damage = 50,

        // inputsPos = {{1, 0}}
        connectionsPos = {{1, 0}}

    },
}

AddEnergy :: proc(building: ^BuildingInstance, value: f32) -> f32 {
    data := &Buildings[building.dataIdx]
    spaceLeft := data.energyStorage - building.currentEnergy
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