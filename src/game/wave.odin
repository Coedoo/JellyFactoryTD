package game

import dm "../dmcore"
import sa "core:container/small_array"

MAX_WAVES :: 100

EnemyWave :: struct {
    count: int,
    spawnTime: f32,
}

Wave :: struct {
    spawnPointIdx: int,
    enemies: [EnemyType]EnemyWave
}

EnemyWaveState :: struct {
    spawnedCount: int,
    timer: f32,

    fullySpawned: bool
}

WaveState :: struct {
    waveIdx: int,
    fullySpawned: bool,
    enemies: [EnemyType]EnemyWaveState
}

StartNextWave :: proc() {
    if gameState.nextWaveIdx >= gameState.loadedLevel.waves.len {
        return
    }

    state := WaveState {
        waveIdx = gameState.nextWaveIdx
    }

    sa.append(&gameState.wavesState, state)
    gameState.nextWaveIdx += 1
}