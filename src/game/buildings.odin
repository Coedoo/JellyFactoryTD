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

        outputsPos = {{1, 0}}
    },

    {
        name = "Test 2",
        spriteName = "buildings.png",
        spriteRect = {32, 0, 32, 32},

        size = {1, 1},

        flags = {.Attack, .ProduceEnergy},

        energyStorage = 100,
        energyProduction = 5,

        range = 3,
        energyRequired = 10,
        reloadTime = 0.2,
    },
}