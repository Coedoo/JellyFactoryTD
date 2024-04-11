package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

import "../ldtk"

BuildingSprites :: enum {
    Solar1,
}

Building :: struct {
    name: string,
    spriteName: string,
    spriteRect: dm.RectInt,

    size: iv2,
}

BuildingInstance :: struct {
    using definition: Building,
    gridPos: iv2,
}


Buildings := [?]Building {
    {
        name = "Test 1",
        spriteName = "buildings.png",
        spriteRect = {0, 0, 32, 32},

        size = {1, 1}
    },

    {
        name = "Test 2",
        spriteName = "buildings.png",
        spriteRect = {32, 0, 32, 32},

        size = {2, 2}
    },
}