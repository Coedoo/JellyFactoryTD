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

    EnergyModifier,

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

TargetingMethod :: enum {
    LowestPathDist,
    KeepTarget,
    Closest,
}

Building :: struct {
    name: string,
    spriteName: string,
    spriteRect: dm.RectInt,

    turretSpriteRect: dm.RectInt,
    turretSpriteOrigin: v2,

    flags: BuildignFlags,
    // restrictedTiles: TileFlags,

    size: iv2,

    cost: int,

    // Energy
    energyStorage: f32,
    energyProduction: f32,

    packetSize: f32,
    packetSpawnInterval: f32,

    balanceType: EnergyBalanceType,

    // Attack
    attackType: AttackType,
    range: f32,
    damage: f32,
    energyRequired: f32,
    reloadTime: f32,
    attackRadius: f32,

    // energy modifier
    energyModifier: EnergyModifier,
}

BuildingInstance :: struct {
    // using definition: Building,
    handle: BuildingHandle,
    dataIdx: int,

    gridPos: iv2,
    position: v2,

    // energy production
    producedEnergyType: EnergyType,
    currentEnergy: EnergySet,

    packetSpawnTimer: f32,

    requiredEnergyFractions: [EnergyType]f32,

    // attack
    targetingMethod: TargetingMethod,
    attackTimer: f32,
    targetEnemy: EnemyHandle,

    firePosition: v2,
    fireTimer: f32,

    // turretAngle: f32,
    // targetTurretAngle: f32,

    // energy usage
    lastUsedSourceIdx: int,
    energySources: [dynamic]BuildingHandle,
    energyTargets: [dynamic]BuildingHandle,

    // energyParticlesTimer: f32,
    energyParticles: dm.ParticleSystem,

    requestedEnergyQueue: [dynamic]EnergyRequest,
}

EnergyModifier :: union {
    SpeedUpModifier,
    ChangeColorModifier,
}

SpeedUpModifier :: struct {
    costPercent: f32,
    multiplier: f32,
}

ChangeColorModifier :: struct {
    costPercent: f32,
    targetType: EnergyType,
}


EnergyParticleSystem := dm.ParticleSystem{
    maxParticles = 128,
    lifetime = 3,

    // startColor = dm.WHITE,
    color = dm.WHITE,
    // color = dm.ColorKeysOverLifetime{
    //     keysCount = 2,
    //     keys = {
    //         0 = {time = 0, value = dm.WHITE},
    //         1 = {time = 1, value = dm.BLACK},
    //     },
    // },

    startColor = dm.ColorKeysOverLifetime{
        keysCount = 2,
        keys = {
            0 = {time = 0, value = dm.WHITE},
            1 = {time = 1, value = dm.BLACK},
        },
    },

    startSize = .4,
    size = 1,

    startSpeed = 0.5,

    emitRate = 10,
}


GetBuilding :: proc(handle: BuildingHandle) -> (^BuildingInstance, Building) {
    instance, ok := dm.GetElementPtr(gameState.spawnedBuildings, handle)
    if ok == false {
        return nil, {}
    }

    return instance, Buildings[instance.dataIdx]
}

HasFlag :: proc(building: BuildingInstance, flag: BuildingFlag) -> bool {
    return flag in Buildings[building.dataIdx].flags
}

HasFlagHandle :: proc(handle: BuildingHandle, flag: BuildingFlag) -> bool {
    building := dm.GetElement(gameState.spawnedBuildings, handle)
    return flag in Buildings[building.dataIdx].flags
}

GetConnectedBuildings :: proc(startCoord: iv2, connectionPoints: ^map[BuildingHandle]iv2 = nil, allocator := context.allocator) -> []BuildingHandle {
    queue := make([dynamic]iv2, 0, 16, allocator = context.temp_allocator)
    visited := make([dynamic]iv2, 0, 16, allocator = context.temp_allocator)

    buildingsInNetwork := make([dynamic]BuildingHandle, 0, 16, allocator = allocator)

    append(&queue, startCoord)

    for len(queue) > 0 {
        coord := pop(&queue)
        tile := GetTileAtCoord(coord)

        append(&visited, coord)

        neighbours := GetNeighbourTiles(coord, context.temp_allocator)
        for neighbour in neighbours {
            delta := neighbour.gridPos - coord
            dir := VecToDir(delta)

            canBeAdded := dir in tile.pipeDir && (ReverseDir[dir] in neighbour.pipeDir || ReverseDir[dir] in neighbour.pipeBridgeDir)
            canBeAdded ||= dir in tile.pipeBridgeDir && (ReverseDir[dir] in neighbour.pipeDir || ReverseDir[dir] in neighbour.pipeBridgeDir)
            canBeAdded &&= slice.contains(visited[:], neighbour.gridPos) == false

            if canBeAdded
            {
                append(&queue, neighbour.gridPos)
            }

            if (dir in tile.pipeDir) &&
               neighbour.building != {} &&
               slice.contains(buildingsInNetwork[:], neighbour.building) == false
            {
                append(&buildingsInNetwork, neighbour.building)
                if connectionPoints != nil {
                    connectionPoints[neighbour.building] = neighbour.gridPos
                }
            }
        }
    }

    return buildingsInNetwork[:]
}

CheckBuildingConnection :: proc(startCoord: iv2) {
    connectionPoints := make(map[BuildingHandle]iv2, allocator = context.temp_allocator)
    buildingsInNetwork := GetConnectedBuildings(startCoord, &connectionPoints, allocator = context.temp_allocator)

    for sourceHandle in buildingsInNetwork {
        source := dm.GetElementPtr(gameState.spawnedBuildings, sourceHandle) or_continue
        sourceData := Buildings[source.dataIdx]

        if .SendsEnergy in sourceData.flags == false {
            continue
        }

        for targetHandle in buildingsInNetwork {
            if sourceHandle != targetHandle {
                target := dm.GetElementPtr(gameState.spawnedBuildings, targetHandle) or_continue
                targetData := Buildings[target.dataIdx]

                if .RequireEnergy in targetData.flags {
                    path := CalculatePath(connectionPoints[sourceHandle], connectionPoints[targetHandle], PipePredicate)

                    if path != nil {
                        key := PathKey{ source.handle, target.handle }
                        gameState.pathsBetweenBuildings[key] = path

                        if slice.contains(source.energyTargets[:], targetHandle) == false {
                            append(&source.energyTargets, targetHandle)
                        }

                        if slice.contains(target.energySources[:], sourceHandle) == false {
                            append(&target.energySources, sourceHandle)
                        }
                    }
                }
            }
        }
    }

    maxBuildings := len(gameState.spawnedBuildings.elements)
    affectedTargets := make([dynamic]^BuildingInstance, 0, maxBuildings, context.temp_allocator)
    visited := make([dynamic]BuildingHandle, 0, maxBuildings, context.temp_allocator)
    stack := make([dynamic]^BuildingInstance, 0, maxBuildings, context.temp_allocator)

    // Find all affected targets: the ones in the network, as well as their targets
    for targetHandle in buildingsInNetwork {
        target := dm.GetElementPtr(gameState.spawnedBuildings, targetHandle) or_continue
        if HasFlag(target^, .RequireEnergy) {
            append(&stack, target)
        }
    }

    for len(stack) > 0 {
        building := pop(&stack)
        append(&affectedTargets, building)

        for targetHandle in building.energyTargets {
            target := dm.GetElementPtr(gameState.spawnedBuildings, targetHandle) or_continue
            if slice.contains(affectedTargets[:], target) ||
               slice.contains(stack[:], target)
            {
                continue
            }

            append(&stack, target)
        }
    }


    // travel upwards to find all energy sources
    for target in affectedTargets {
        clear(&visited)

        fractions: [EnergyType]f32

        append(&visited, target.handle)

        // fmt.println("For target: ", Buildings[target.dataIdx].name, target.handle)
        for sourceHandle in target.energySources {
            source := dm.GetElementPtr(gameState.spawnedBuildings, sourceHandle) or_continue
            append(&stack, source)
            if HasFlag(source^, .ProduceEnergy) == false {
                append(&visited, sourceHandle)
            }
        }

        sum: f32
        for len(stack) > 0 {
            source := pop(&stack)

            // fmt.println("Visited:", source.handle, Buildings[source.dataIdx].name)

            if HasFlag(source^, .ProduceEnergy) {
                // type := Buildings[source.dataIdx].producedEnergyType
                type := source.producedEnergyType
                fractions[type] += 1

                sum += 1
            }

            for parentHandle in source.energySources {
                if slice.contains(visited[:], parentHandle) {
                    continue
                }

                parent := dm.GetElementPtr(gameState.spawnedBuildings, parentHandle) or_continue
                append(&stack, parent)
                if HasFlag(parent^, .ProduceEnergy) == false {
                    append(&visited, parentHandle)
                }
            }
        }

        if sum != 0 {
            for &f in fractions {
                f = f / sum * Buildings[target.dataIdx].energyStorage
            }
        }

        target.requiredEnergyFractions = fractions
    }
}
