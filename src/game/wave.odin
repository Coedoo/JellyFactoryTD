package game

import dm "../dmcore"

EnemiesSeries :: struct {
    enemyName: string,
    count: int,
    timeBetweenSpawns: f32,
}

LevelWaves :: struct {
    levelName: string,
    waves: [][]EnemiesSeries,
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

StartNextWave :: proc() {
    if gameState.currentWaveIdx < len(gameState.loadedLevel.waves.waves) {
        gameState.currentWaveIdx += 1
    }
}