package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

EnergyType :: enum {
    Blue,
    Green,
    Cyan,
}

EnergyColor := [EnergyType]dm.color {
    .Blue = dm.BLUE,
    .Green = dm.GREEN,
    .Cyan = dm.SKYBLUE,
}

EnergyPacketHandle :: distinct dm.Handle
EnergyPacket :: struct {
    handle: EnergyPacketHandle,
    pathKey: PathKey,
    using pathFollower: PathFollower,

    speed: f32,
    energyType: EnergyType,
    energy: f32,
}

EnergySet :: distinct [EnergyType]f32

BuildingEnergy :: proc(building: ^BuildingInstance) -> (sum: f32) {
    for e in building.currentEnergy {
        sum += e
    }

    return sum
}

AddEnergy :: proc(building: ^BuildingInstance, type: EnergyType, value: f32) -> f32 {
    data := &Buildings[building.dataIdx]

    currentEnergy := BuildingEnergy(building)
    spaceLeft := data.energyStorage - currentEnergy
    clamped := clamp(value, 0, spaceLeft)

    building.currentEnergy[type] += clamped
    return value - clamped
}

RemoveEnergyFromBuilding :: proc(building: ^BuildingInstance, toRemove: f32) -> EnergySet {
    currentEnergy := BuildingEnergy(building)

    ret: EnergySet
    for type in EnergyType {
        ret[type] = toRemove * (building.currentEnergy[type] / currentEnergy)
        building.currentEnergy[type] -= ret[type]
    }

    return ret
}