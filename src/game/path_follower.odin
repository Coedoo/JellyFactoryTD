package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

PathKey :: struct {
    from: BuildingHandle,
    to: BuildingHandle,
}

PathFollower :: struct {
    path: []iv2,
    nextPointIdx: int,
    position: v2,

    finishedPath: bool,
    enteredNewSegment: bool,
}

SpawnPath :: struct {
    spawnCoord: iv2,
    path: []iv2,
}

UpdateFollower :: proc(follower: ^PathFollower, speed: f32) {
    if follower.finishedPath {
        return
    }

    dist := speed * f32(dm.time.deltaTime)
    target := CoordToPos(follower.path[follower.nextPointIdx])

    follower.enteredNewSegment = false

    pos, distLeft := dm.MoveTowards(follower.position, target, dist)
    if distLeft != 0 {
        follower.nextPointIdx += 1
        if follower.nextPointIdx == len(follower.path) {
            follower.finishedPath = true
        }
        else {
            target = CoordToPos(follower.path[follower.nextPointIdx])
            pos, distLeft = dm.MoveTowards(pos, target, distLeft)

            follower.enteredNewSegment = true
        }
    }

    follower.position = pos
}

DistanceLeft :: proc(follower: PathFollower) -> f32 {
    nextPos := CoordToPos(follower.path[follower.nextPointIdx])
    dist := glsl.distance(follower.position, nextPos)

    for i := follower.nextPointIdx; i < len(follower.path) - 1; i += 1 {
        a := CoordToPos(follower.path[i])
        b := CoordToPos(follower.path[i + 1])
        dist += glsl.distance(a, b)
    }

    return dist
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

IsInDistance :: proc(playerPos: v2, target: iv2) -> bool {
    playerPos := WorldPosToCoord(playerPos)
    delta := target - playerPos
    return delta.x * delta.x + delta.y * delta.y <= BUILDING_DISTANCE * BUILDING_DISTANCE
}