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

PrevDir := [Direction]Direction {
    .East  = .North, 
    .North = .West, 
    .West  = .South, 
    .South = .East
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

DirToVec := [Direction]iv2 {
    .East  = {1,  0}, 
    .North = {0,  1}, 
    .West  = {-1, 0},
    .South = {0, -1},
}

VecToDir :: proc(vec: iv2) -> Direction {
    if abs(vec.x) > abs(vec.y) {
        return vec.x < 0 ? .West : .East
    }
    else {
        return vec.y < 0 ? .South : .North
    }
}

// @TODO: I'm pretty sure that it can be done easier
RotateByDir :: proc(set: DirectionSet, direction: Direction) -> (ret: DirectionSet) {
    iter: int
    switch direction {
    case .East:  iter = 0
    case .North: iter = 1
    case .West:  iter = 2
    case .South: iter = 3
    }

    ret = set
    for i in 0..<iter {
        new: DirectionSet
        for dir in ret {
            new += { NextDir[dir] }
        }

        ret = new
    }

    return
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
            if packet.pathKey.to == handle {
                amount += packet.energy
            }
        }
    }

    return
}

PathsEqual :: proc(pathA: []iv2, pathB: []iv2) -> bool {
    if len(pathA) != len(pathB) {
        return false
    }

    for i in 0..<len(pathA) {
        if pathA[i] != pathB[i] {
            return false
        }
    }

    return true
}