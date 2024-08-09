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
    SendsEnergy,
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
    restrictedTiles: []TileType,

    size: iv2,

    cost: int,

    connections: DirectionSet,

    // Energy
    producedEnergyType: EnergyType,
    energyStorage: f32,
    energyProduction: f32,

    packetSize: f32,
    packetSpawnInterval: f32,

    // Attack
    attackType: AttackType,
    range: f32,
    damage: f32,
    energyRequired: f32,
    reloadTime: f32,
    attackRadius: f32,
}

BuildingInstance :: struct {
    // using definition: Building,
    handle: BuildingHandle,
    dataIdx: int,

    gridPos: iv2,
    position: v2,
    rotation: Direction,

    // energy
    currentEnergy: EnergySet,
    packetSpawnTimer: f32,

    // attack
    attackTimer: f32,
    targetEnemy: EnemyHandle,

    turretAngle: f32,
    targetTurretAngle: f32,

    // connectedBuildings: [dynamic]BuildingHandle,

    lastUsedSourceIdx: int,
    energySources: [dynamic]BuildingHandle,
    energyTargets: [dynamic]BuildingHandle,
}


Buildings := [?]Building {
    {
        name = "Factory 1",
        spriteName = "buildings.png",
        spriteRect = {0, 0, 32, 32},

        size = {1, 1},

        flags = { .ProduceEnergy, .SendsEnergy },

        restrictedTiles = { .Walls },

        cost = 100,

        energyStorage = 100,
        energyProduction = 25,

        packetSize = 10,
        packetSpawnInterval = 0.2,

        connections = {.East, .North, .West, .South},
    },
    
    {
        name = "Factory 2",
        spriteName = "buildings.png",
        spriteRect = {0, 0, 32, 32},

        size = {1, 1},

        flags = { .ProduceEnergy, .SendsEnergy },

        restrictedTiles = { .Walls },

        cost = 100,

        producedEnergyType = .Green,
        energyStorage = 100,
        energyProduction = 25,

        packetSize = 10,
        packetSpawnInterval = 0.2,

        connections = {.East, .North, .West, .South},
    },

    {
        name = "Factory 3",
        spriteName = "buildings.png",
        spriteRect = {0, 0, 32, 32},

        size = {1, 1},

        flags = { .ProduceEnergy, .SendsEnergy },

        restrictedTiles = { .Walls },

        cost = 100,

        producedEnergyType = .Red,
        energyStorage = 100,
        energyProduction = 25,

        packetSize = 10,
        packetSpawnInterval = 0.2,

        connections = {.East, .North, .West, .South},
    },

    {
        name = "Turret 1",
        spriteName = "turret_test_3.png",
        spriteRect = {0, 32, 32, 32},
        turretSpriteRect = {32, 0, 32, 64},
        turretSpriteOrigin = {0.5, 0.75},

        size = {1, 1},

        flags = {.Attack, .RequireEnergy, .RotatingTurret},

        cost = 200,

        energyStorage = 100,
        // energyProduction = 25,

        attackType = .Simple,
        range = 4,
        energyRequired = 8,
        reloadTime = 0.2,
        damage = 50,

        connections = DirHorizontal,
    },

    {
        name = "Cannon 1",
        spriteName = "turret_test_3.png",
        spriteRect = {0, 32, 32, 32},
        turretSpriteRect = {32, 0, 32, 64},
        turretSpriteOrigin = {0.5, 0.75},

        size = {1, 1},

        flags = {.Attack, .RequireEnergy, .RotatingTurret},

        cost = 200,

        energyStorage = 100,
        // energyProduction = 25,

        attackType = .Cannon,

        range = 4,
        energyRequired = 10,
        reloadTime = 0.2,
        damage = 70,
        attackRadius = 3,

        connections = DirHorizontal,
    },
}

GetConnectedBuildings :: proc(startCoord: iv2, allocator := context.allocator) -> []BuildingHandle {
    queue := make([dynamic]iv2, 0, 16, allocator = context.temp_allocator)
    visited := make([dynamic]iv2, 0, 16, allocator = context.temp_allocator)

    buildingsInNetwork := make([dynamic]BuildingHandle, 0, 16, allocator = allocator)

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
               (ReverseDir[dir] in neighbour.wireDir) &&
                slice.contains(visited[:], neighbour.gridPos) == false
            {
                append(&queue, neighbour.gridPos)
                append(&visited, coord)
            }

            if (dir in tile.wireDir) &&
               neighbour.building != {} &&
               slice.contains(buildingsInNetwork[:], neighbour.building) == false
            {
                append(&buildingsInNetwork, neighbour.building)
            }
        }
    }

    return buildingsInNetwork[:]
}

CheckBuildingConnection :: proc(startCoord: iv2) {
    buildingsInNetwork := GetConnectedBuildings(startCoord, context.temp_allocator)

    for handle in buildingsInNetwork {
        building := dm.GetElementPtr(gameState.spawnedBuildings, handle) or_continue

        clear(&building.energyTargets)
        clear(&building.energySources)
    }

    for handleA in buildingsInNetwork {
        building := dm.GetElementPtr(gameState.spawnedBuildings, handleA) or_continue
        data := Buildings[building.dataIdx]

        if (.SendsEnergy in data.flags) == false {
            continue
        }

        for handleB in buildingsInNetwork {
            if handleA != handleB {

                otherBuilding := dm.GetElementPtr(gameState.spawnedBuildings, handleB) or_continue
                otherData := Buildings[otherBuilding.dataIdx]

                if .RequireEnergy in otherData.flags {
                    append(&building.energyTargets, handleB)
                    append(&otherBuilding.energySources, handleA)

                    key := PathKey{ building.handle, otherBuilding.handle }
                    path := CalculatePath(building.gridPos, otherBuilding.gridPos, WirePredicate)
                    gameState.pathsBetweenBuildings[key] = path
                }
            }
        }
    }
}