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
    sprite: BuildingSprites,
}


Buildings := [?]Building {
    {
        "Solar1", .Solar1
    },

}