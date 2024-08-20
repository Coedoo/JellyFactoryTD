package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

EnergyType :: enum {
    None,
    Blue,
    Green,
    // Cyan,
    Red,
}

EnergyColor := [EnergyType]dm.color {
    .None = dm.MAGENTA,
    .Blue = dm.BLUE,
    .Green = dm.GREEN,
    // .Cyan = dm.SKYBLUE,
    .Red = dm.RED,
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

EnergyBalanceType :: enum {
    None,
    Balanced,
    Full,
}

EnergyRequest :: struct {
    to: BuildingHandle,
    energy: f32,
    type: EnergyType,
}

BuildingEnergy :: proc(building: ^BuildingInstance) -> (sum: f32) {
    for e in building.currentEnergy {
        sum += e
    }

    return sum
}

BiggestEnergy :: proc(building: ^BuildingInstance) -> (energy: f32, type: EnergyType) {
    for e, i in building.currentEnergy {
        if e >= energy {
            energy = e
            type = EnergyType(i)
        }
    }

    return
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