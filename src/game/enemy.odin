package game

import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

import dm "../dmcore"

EnemyHandle :: distinct dm.Handle

Enemy :: struct {
    name: string,
    speed: f32,
    maxHealth: f32,

    tint: dm.color,

    moneyValue: int,

    damage: int,
}

EnemyInstance :: struct {
    handle: EnemyHandle,

    statsIdx: int,

    // position: v2,
    // pathPointIdx: int,
    using pathFollower: PathFollower,

    poisonValue: DamageEffectValues,
    slowValue: DamageEffectValues,

    health: f32,
}

DamageEffectValues :: struct {
    value: f32,
    timeLeft: f32,
}

SpawnEnemy :: proc {
    SpawnEnemyByIndex,
    SpawnEnemyByName,
}

SpawnEnemyByIndex :: proc(idx: int) -> ^EnemyInstance {
    enemy := dm.CreateElement(&gameState.enemies)

    stats := Enemies[idx]
    enemy.statsIdx = idx
    enemy.health = stats.maxHealth
    enemy.position = dm.ToV2(gameState.path[0]) + {0.5, 0.5}

    enemy.path = gameState.path

    return enemy
}

SpawnEnemyByName :: proc(name: string) -> ^EnemyInstance {
    // @TODO: hashmap for enemy names -> indices
    for enemy, i in Enemies {
        if enemy.name == name {
            return SpawnEnemyByIndex(i)
        }
    }

    return nil
}

UpdateEnemy :: proc(enemy: ^EnemyInstance) {
    enemyStat := Enemies[enemy.statsIdx]

    speed := enemyStat.speed
    if enemy.slowValue.timeLeft > 0 {
        speed = speed * (1 - enemy.slowValue.value)
        enemy.slowValue.timeLeft -= dm.time.deltaTime
    }

    if enemy.poisonValue.timeLeft > 0 {
        enemy.poisonValue.timeLeft -= dm.time.deltaTime
    }

    UpdateFollower(enemy, speed)

    if enemy.finishedPath {
        enemy.finishedPath = false

        enemy.nextPointIdx = 0
        enemy.position = CoordToPos(enemy.path[0])

        gameState.hp -= enemyStat.damage
    }
}

DamageEnemy :: proc(enemy: ^EnemyInstance, damage: f32, usedEnergy: EnergySet) {
    enemy.health -= damage

    if enemy.health <= 0 {
        gameState.money += Enemies[enemy.statsIdx].moneyValue
        dm.FreeSlot(&gameState.enemies, enemy.handle)

        return
    }

    if usedEnergy[.Green] > 0 {
        enemy.poisonValue.value = 1
        enemy.poisonValue.timeLeft = 5
    }

    if usedEnergy[.Cyan] > 0 {
        enemy.slowValue.value = 0.25
        enemy.slowValue.timeLeft = 5
    }
}

FindClosestEnemy :: proc(pos: v2, radius: f32) -> (handle: EnemyHandle) {
    if len(gameState.enemies.elements) == 0 {
        return
    }

    handle = gameState.enemies.elements[0].handle
    closestDist := max(f32)


    for e in gameState.enemies.elements {
        dist := glsl.distance(pos, e.position)
        if dist < radius && dist < closestDist {
            handle = e.handle
            closestDist = dist
        }
    }

    return
}

FindEnemiesInRange :: proc(center: v2, radius: f32, allocator := context.temp_allocator) -> []^EnemyInstance {
    enemies := make([dynamic]^EnemyInstance, 0, 5, allocator)

    for &e in gameState.enemies.elements {
        dist := glsl.distance(center, e.position)
        if dist < radius {
            append(&enemies, &e)
        }
    }

    return enemies[:]
}