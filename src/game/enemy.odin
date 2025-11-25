package game

import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

import dm "../dmcore"

EnemyHandle :: distinct dm.Handle

EnemyType :: enum {
    Regular,
    Big,
    Fast,
}

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

    type: EnemyType,

    // position: v2,
    // pathPointIdx: int,
    spawnPointCoord: iv2,
    using pathFollower: PathFollower,

    poisonValue: DamageEffectValues,
    slowValue: DamageEffectValues,

    health: f32,
}

DamageEffectValues :: struct {
    value: f32,
    timeLeft: f32,
}

SpawnEnemy :: proc(type: EnemyType, spawnPointIdx: int) -> ^EnemyInstance {
    enemy := dm.CreateElement(&gameState.enemies)

    stats := Enemies[type]
    enemy.type = type
    enemy.health = stats.maxHealth

    spawnPoint := gameState.loadedLevel.spawnPoints.data[spawnPointIdx]
    path := GetPath(spawnPoint.coord)


    enemy.position = CoordToPos(path[0])
    enemy.spawnPointCoord = spawnPoint.coord
    enemy.path = path

    return enemy
}


UpdateEnemy :: proc(enemy: ^EnemyInstance) {
    enemyStat := Enemies[enemy.type]

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
        enemy.path = GetPath(enemy.spawnPointCoord)
        enemy.position = CoordToPos(enemy.path[0])

        gameState.hp -= enemyStat.damage
    }
}

DamageEnemy :: proc(enemy: ^EnemyInstance, damage: f32, usedEnergy: EnergySet) {
    enemy.health -= damage

    if enemy.health <= 0 {
        gameState.money += Enemies[enemy.type].moneyValue
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