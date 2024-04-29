package game

import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

import dm "../dmcore"

EnemyHandle :: distinct dm.Handle

Enemy :: struct {
    handle: EnemyHandle,

    speed: f32,

    position: v2,
    pathPointIdx: int,
}

UpdateEnemy :: proc(enemy: ^Enemy) {
    // enemy, ok := dm.GetElementPtr(gameState.enemies, enemyHandle)
    // if ok == false {
    //     return
    // }


    dist := enemy.speed * f32(dm.time.deltaTime)
    target := dm.ToV2(gameState.path[enemy.pathPointIdx]) + {0.5, 0.5}

    pos, distLeft := dm.MoveTowards(enemy.position, target, dist)
    for distLeft != 0 {
        enemy.pathPointIdx += 1
        if enemy.pathPointIdx == len(gameState.path) {
            enemy.pathPointIdx = 0
            pos = dm.ToV2(gameState.path[0]) + {0.5, 0.5}
            break
        }

        target = dm.ToV2(gameState.path[enemy.pathPointIdx]) + {0.5, 0.5}
        pos, distLeft = dm.MoveTowards(pos, target, distLeft)
    }

    enemy.position = pos
}