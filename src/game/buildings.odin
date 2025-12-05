package game

import "base:builtin"
import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

import sa "core:container/small_array"


MAX_SLOTS :: 4

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

SlotIOType :: enum {
    Input,
    Output,
}

SlotIO :: distinct bit_set[SlotIOType]
SlotIn    :: SlotIO{ .Input }
SlotOut   :: SlotIO{ .Output }
SlotInOut :: SlotIO{ .Input, .Output }


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

BuildingEnergySlot :: struct {
    using energy: Energy,

    io: SlotIO,
    lastSourceIdx: int,
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
    energySlotsIO: []SlotIO,
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

    energySlotsCount: int,
    energySlots: [MAX_SLOTS]BuildingEnergySlot,

    // energy production
    // producedEnergyLevel: int,
    // producedEnergyType: [EnergyType]int,

    packetSpawnTimer: f32,

    // .Attack
    lastUsedSlotIdx: int,
    targetingMethod: TargetingMethod,
    attackTimer: f32,
    targetEnemy: EnemyHandle,

    firePosition: v2,
    fireTimer: f32,

    // turretAngle: f32,
    // targetTurretAngle: f32,

    // .Require Energy
    lastUsedSourceIdx: int,
    // requiredEnergyFractions: [EnergyType]f32,

    energySources: [dynamic]BuildingHandle,
    energyTargets: [dynamic]BuildingHandle,

    // energyParticlesTimer: f32,
    energyParticles: dm.ParticleSystem,

    requestedEnergyQueue: [dynamic]EnergyRequest,
}

EnergyModifier :: union {
    SpeedUpModifier,
    // ChangeColorModifier,
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

Slots :: proc(building: ^BuildingInstance) -> []BuildingEnergySlot {
    return building.energySlots[:building.energySlotsCount]
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

    // if len(buildingsInNetwork) != 0 {
    //     fmt.println(buildingsInNetwork)
    // }

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


    foundTypes := make([dynamic]Energy, 0, 16, allocator = context.temp_allocator)
    // Fill energy slots for the target
    for target in affectedTargets {
        buildingData := Buildings[target.dataIdx]

        // Sort energy sources by path length
        context.user_ptr = &target.handle
        slice.sort_by_cmp(target.energySources[:], proc(a, b: BuildingHandle) -> slice.Ordering {
            targetHandle := cast(^BuildingHandle) context.user_ptr
            aLen := len(gameState.pathsBetweenBuildings[PathKey{a, targetHandle^}])
            bLen := len(gameState.pathsBetweenBuildings[PathKey{b, targetHandle^}])

            return slice.cmp(aLen, bLen)
        })


        clear(&foundTypes)
        for sourceHandle in target.energySources {
            source, sourceData := GetBuilding(sourceHandle)
            for sourceSlot in Slots(source) {
                if .Output in sourceSlot.io {
                    if dm.SliceContainsComp(foundTypes[:], sourceSlot.energy, EnergyTypeEqual) == false {
                        append(&foundTypes, sourceSlot.energy)
                    }
                }
            }
        }

        // if len(foundTypes) != 0 {
        //     fmt.println(foundTypes)
        // }

        newSlots: [MAX_SLOTS]BuildingEnergySlot
        for &s, i in newSlots {
            s.io = buildingData.energySlotsIO[i]
        }

        idx: int
        for type, i in foundTypes {
            if i >= target.energySlotsCount {
                break
            }

            // newSlots[i].io = buildingData.energySlotsIO[i]
            if .Input not_in newSlots[i].io {
                continue
            }

            newSlots[idx].level = type.level
            newSlots[idx].types = type.types

            for targetSlot in Slots(target) {
                if EnergyTypeEqual(targetSlot, newSlots[idx]) {
                    newSlots[idx].amount = targetSlot.amount
                    break
                }
            }

            idx += 1
        }

        target.energySlots = newSlots
    }
}
