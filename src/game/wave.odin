package game

import dm "../dmcore"
import sa "core:container/small_array"

MAX_WAVES :: 100

SpawnWave :: struct {
    spawnCoord: iv2,
    spawnTime: f32,

    enemyType: EnemyType,
    count: int,
}

Wave :: struct {
    spawnWaves: sa.Small_Array(MAX_SPAWN_POINTS, SpawnWave),
}

SpawnWaveState :: struct {
    spawnedCount: int,
    spawnTimer: f32,
}

WaveState :: struct {
    waveIdx: int,
    fullySpawned: bool,
    spawnStates: sa.Small_Array(MAX_SPAWN_POINTS, SpawnWaveState),
}


StartNextWave :: proc() {
    idx := gameState.nextWaveIdx
    if idx >= gameState.loadedLevel.waves.len {
        return
    }

    state := WaveState {
        waveIdx = idx
    }

    state.spawnStates.len = gameState.loadedLevel.waves.data[idx].spawnWaves.len

    sa.append(&gameState.wavesState, state)
    gameState.nextWaveIdx += 1
}