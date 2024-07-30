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

ReverseDir := [Direction]Direction {
    .East  = .West,
    .West  = .East,
    .North = .South,
    .South = .North,
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

CoordToPos :: proc(coord: iv2) -> v2 {
    return dm.ToV2(coord) + {0.5, 0.5}
}

PathKey :: struct {
    from: BuildingHandle,
    to: BuildingHandle,
}

PathFollower :: struct {
    path: []iv2,
    nextPointIdx: int,
    position: v2,
}

UpdateFollower :: proc(follower: ^PathFollower, speed: f32) -> bool {
    dist := speed * f32(dm.time.deltaTime)
    target := CoordToPos(follower.path[follower.nextPointIdx])

    pos, distLeft := dm.MoveTowards(follower.position, target, dist)
    for distLeft != 0 {
        follower.nextPointIdx += 1
        if follower.nextPointIdx == len(follower.path) {
            pos = CoordToPos(follower.path[0])

            return true
        }

        target = CoordToPos(follower.path[follower.nextPointIdx])
        pos, distLeft = dm.MoveTowards(pos, target, distLeft)
    }

    follower.position = pos
    return false
}


GetTransitEnergy :: proc(handle: BuildingHandle) -> (amount: f32) {
    for packet in gameState.energyPackets.elements {
        if dm.IsHandleValid(gameState.energyPackets, packet.handle) {
            if packet.target == handle {
                amount += packet.energy
            }
        }
    }

    return
}