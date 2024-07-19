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

DirectionSet :: distinct bit_set[Direction; u32]

DirVertical   :: DirectionSet{ .North, .South }
DirHorizontal :: DirectionSet{ .West, .East }

DirNE   :: DirectionSet{ .North, .East }
DirNW   :: DirectionSet{ .North, .West }
DirSE   :: DirectionSet{ .South, .East }
DirSW   :: DirectionSet{ .South, .West }

DirSplitter :: DirectionSet{ .East, .North, .West, .South }

NextDir := [Direction]Direction {
    .East  = .South, 
    .North = .East, 
    .West  = .North, 
    .South = .West
}

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

GetOppositeDir :: proc(dir: Direction) -> Direction {
    switch dir {
    case .East:  return .West
    case .West:  return .East
    case .North: return .South
    case .South: return .North
    }

    return nil // to stop compiler from complaining
}