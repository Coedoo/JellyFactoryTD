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

VecToDir :: proc(vec: iv2) -> Direction {
    if abs(vec.x) > abs(vec.y) {
        return vec.x < 0 ? .West : .East
    }
    else {
        return vec.y < 0 ? .South : .North
    }
}