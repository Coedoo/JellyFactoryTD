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

    position: v2,
    pathPointIdx: int,
    health: f32,
}

EnemiesSeries :: struct {
    enemyName: string,
    count: int,
    timeBetweenSpawns: f32,
}

EnemyWave :: struct {
    series: []EnemiesSeries,
}

WaveState :: struct {
    fullySpawned: bool,
    seriesStates: []SeriesState,
}

SeriesState :: struct {
    timer: f32,
    count: int,
    fullySpawned: bool,
}

Enemies := [?]Enemy {
    {
        name = "Test 1",
        speed = 8,
        maxHealth = 100,
        tint = dm.RED,
        moneyValue = 30,
        damage = 10,
    },

    {
        name = "Test 2",
        speed = 5,
        maxHealth = 200,
        tint = dm.GREEN,
        moneyValue = 70,
        damage = 25,
    },
}

Waves := [?]EnemyWave {
    {
        series = {
            {"Test 1", 20, 0.15},
            {"Test 2", 10, 0.7},
        },
    },
    {
        series = {
            {"Test 1", 40, 0.1},
            {"Test 1", 5, 0.5},
        },
    }
}



SpawnEnemy :: proc {
    SpawnEnemyByIndex,
    SpawnEnemyByName,
}

SpawnEnemyByIndex :: proc(idx: int) -> ^EnemyInstance {
    enemy := dm.CreateElement(gameState.enemies)

    stats := Enemies[idx]
    enemy.statsIdx = idx
    enemy.health = stats.maxHealth
    enemy.position = dm.ToV2(gameState.path[0]) + {0.5, 0.5}

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
    // enemy, ok := dm.GetElementPtr(gameState.enemies, enemyHandle)
    // if ok == false {
    //     return
    // }

    enemyStat := Enemies[enemy.statsIdx]

    dist := enemyStat.speed * f32(dm.time.deltaTime)
    target := dm.ToV2(gameState.path[enemy.pathPointIdx]) + {0.5, 0.5}

    pos, distLeft := dm.MoveTowards(enemy.position, target, dist)
    for distLeft != 0 {
        enemy.pathPointIdx += 1
        if enemy.pathPointIdx == len(gameState.path) {
            enemy.pathPointIdx = 0
            pos = dm.ToV2(gameState.path[0]) + {0.5, 0.5}

            gameState.hp -= enemyStat.damage

            break
        }

        target = dm.ToV2(gameState.path[enemy.pathPointIdx]) + {0.5, 0.5}
        pos, distLeft = dm.MoveTowards(pos, target, distLeft)
    }

    enemy.position = pos
}

DamageEnemy :: proc(enemy: ^EnemyInstance, damage: f32) {
    enemy.health -= damage

    if enemy.health <= 0 {
        gameState.money += Enemies[enemy.statsIdx].moneyValue
        dm.FreeSlot(gameState.enemies, enemy.handle)
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

FindEnemiesInRange :: proc(center: v2, radius: f32, allocator := context.allocator) -> []EnemyHandle {
    enemies := make([dynamic]EnemyHandle, 0, 5, allocator)

    for e in gameState.enemies.elements {
        dist := glsl.distance(center, e.position)
        if dist < radius {
            append(&enemies, e.handle)
        }
    }

    return enemies[:]
}

//////////////////

StartNextWave :: proc() {
    if gameState.currentWaveIdx < len(Waves) {
        gameState.currentWaveIdx += 1
    }
}