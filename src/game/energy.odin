package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

import sa "core:container/small_array"

EnergyType :: enum {
    None,
    Blue,  // standard
    Green, // poison
    Cyan,  // slow
    Red,   // damage boost...?
}

EnergyColor := [EnergyType]dm.color {
    .None = dm.MAGENTA,
    .Blue = dm.BLUE,
    .Green = dm.GREEN,
    .Cyan = dm.SKYBLUE,
    .Red = dm.RED,
}

Energy :: struct {
    level: i32,
    amount: f32,
    types: [EnergyType]int,
}

EnergyPacketHandle :: distinct dm.Handle
EnergyPacket :: struct {
    handle: EnergyPacketHandle,
    pathKey: PathKey,
    using pathFollower: PathFollower,

    speed: f32,

    // energyType: EnergyType,
    // energy: f32,
    energy: Energy,
}

EnergyBalanceType :: enum {
    None,
    Balanced,
    Full,
}

EnergyRequest :: struct {
    to: BuildingHandle,
    energy: Energy
}

EnergyTypeEqual :: proc(a, b: Energy) -> bool {
    return a.level == b.level && a.types == b.types
}

BuildingEnergy :: proc(building: ^BuildingInstance) -> (sum: f32) {
    for e in Slots(building) {
        sum += e.amount
    }

    return sum
}

MaxEnergyPerSlot :: proc(building: ^BuildingInstance) -> (energy: f32) {
    data := Buildings[building.dataIdx]
    return data.energyStorage / f32(ActiveSlotsCount(building))
}

ActiveSlotsCount :: proc(building: ^BuildingInstance) -> (ret: int) {
    for e in Slots(building) {
        if e.types != {} {
            ret += 1
        }
    }

    return
}

GetEnergyPtr :: proc(building: ^BuildingInstance, type: [EnergyType]int, lvl: i32) -> ^Energy {
    for &e in Slots(building) {
        if e.types == type && e.level == lvl {
            return &e
        }
    }

    return nil
}

AddEnergy :: proc(building: ^BuildingInstance, energy: Energy) -> bool {
    for &e in Slots(building) {
        if EnergyTypeEqual(e, energy) {
            e.amount += energy.amount
            return true
        }
    }

    return false

    // not found - add new entry
    // sa.append(&building.energySlots, energy)

    // data := &Buildings[building.dataIdx]

    // energySlots := BuildingEnergy(building)
    // spaceLeft := data.energyStorage - energySlots
    // clamped := clamp(value, 0, spaceLeft)

    // building.energySlots[type] += clamped
    // return value - clamped
}

// RemoveEnergyFromBuilding :: proc(building: ^BuildingInstance, toRemove: f32) -> (ret: [EnergyType]f32) {
//     energySlots := BuildingEnergy(building)

//     for type in EnergyType {
//         ret[type] = toRemove * (building.energySlots[type] / energySlots)
//         building.energySlots[type] -= ret[type]
//     }

//     return ret
// }

GetEnergyColor :: proc {
    GetEnergyColorAmount,
    GetEnergyColorProportions,
}

GetEnergyColorAmount :: proc(value: [EnergyType]f32) -> (color: dm.color) {
    sum: f32
    for energy in value {
        sum += energy
    }

    if sum == 0 {
        return {0, 0, 0, 1}
    }

    for type in EnergyType {
        color += (value[type] / sum) * EnergyColor[type]
    }

    return
}

GetEnergyColorProportions :: proc(value: [EnergyType]int) -> (color: dm.color) {
    sum: f32
    for energy in value {
        sum += f32(energy)
    }

    if sum == 0 {
        return {0, 0, 0, 1}
    }

    for type in EnergyType {
        color += (f32(value[type]) / sum) * EnergyColor[type]
    }

    return
}

