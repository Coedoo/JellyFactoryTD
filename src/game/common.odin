package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

Direction :: enum {
    East,
    North,
    West,
    South,
}

DirectionSet :: distinct bit_set[Direction]

DirToRot := [Direction]f32 {
    .East  = 0, 
    .North = 90, 
    .West  = 180, 
    .South = 270
}