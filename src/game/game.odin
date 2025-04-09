package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"
import "core:mem"

import "../ldtk"

v2 :: dm.v2
iv2 :: dm.iv2

GameStage :: enum {
    MainMenu,
    Gameplay,
}

GameState :: struct {
    stage: GameStage,
    menuStage: MenuStage,


    levelArena: mem.Arena,
    levelAllocator: mem.Allocator,

    levels: []Level,
    level: ^Level, // currentLevel

    using levelState: struct {
        spawnedBuildings: dm.ResourcePool(BuildingInstance, BuildingHandle),
        enemies: dm.ResourcePool(EnemyInstance, EnemyHandle),
        energyPackets: dm.ResourcePool(EnergyPacket, EnergyPacketHandle),

        money: int,
        hp: int,

        playerPosition: v2,

        selectedTile: iv2,

        buildUpMode: BuildUpMode,
        selectedBuildingIdx: int,
        buildingPipeDir: DirectionSet,

        currentWaveIdx: int,
        levelWaves: LevelWaves,
        wavesState: []WaveState,

        levelFullySpawned: bool,

        pathsBetweenBuildings: map[PathKey][]iv2,

        // VFX
        turretFireParticle: dm.ParticleSystem,

        // Path
        pathArena: mem.Arena,
        pathAllocator: mem.Allocator,

        cornerTiles: []iv2,
        path: []iv2,
    },

    particlesTimers: [EnergyType]f32,
    tileEnergyParticles: [EnergyType]dm.ParticleSystem,

    playerMoveParticles: dm.ParticleSystem,

    playerSprite: dm.Sprite,
    arrowSprite: dm.Sprite,
}

gameState: ^GameState

RemoveMoney :: proc(amount: int) -> bool {
    if gameState.money >= amount {
        gameState.money -= amount
        return true
    }

    return false
}

//////////////

MousePosGrid :: proc() -> (gridPos: iv2) {
    mousePos := dm.ScreenToWorldSpace(dm.input.mousePos)

    gridPos.x = i32(mousePos.x)
    gridPos.y = i32(mousePos.y)

    return
}

@export
PreGameLoad : dm.PreGameLoad : proc(assets: ^dm.Assets) {
    // dm.RegisterAsset("testTex.png", dm.TextureAssetDescriptor{})

    dm.RegisterAsset("level1.ldtk", dm.RawFileAssetDescriptor{})
    dm.RegisterAsset("kenney_tilemap.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("buildings.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("turret_test_4.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("Energy.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("StarParticle.png", dm.TextureAssetDescriptor{})

    dm.RegisterAsset("ship.png", dm.TextureAssetDescriptor{})
    
    dm.RegisterAsset("menu/JellyBackground.png", dm.TextureAssetDescriptor{filter = .Bilinear})
    dm.RegisterAsset("menu/JellyShip.png", dm.TextureAssetDescriptor{filter = .Bilinear})
    dm.RegisterAsset("menu/Tower1.png", dm.TextureAssetDescriptor{filter = .Bilinear})
    dm.RegisterAsset("menu/Tower2.png", dm.TextureAssetDescriptor{filter = .Bilinear})
    dm.RegisterAsset("menu/BackgroundBullet1.png", dm.TextureAssetDescriptor{filter = .Bilinear})
    dm.RegisterAsset("menu/Crossfire.png", dm.TextureAssetDescriptor{filter = .Bilinear})

    dm.platform.SetWindowSize(1200, 900)
}

@(export)
GameHotReloaded : dm.GameHotReloaded : proc(gameState: rawptr) {
    gameState := cast(^GameState) gameState

    gameState.levelAllocator = mem.arena_allocator(&gameState.levelArena)
}

@(export)
GameLoad : dm.GameLoad : proc(platform: ^dm.Platform) {
    gameState = dm.AllocateGameData(platform, GameState)

    EnergyParticleSystem.texture = dm.GetTextureAsset("Energy.png")

    levelMem := make([]byte, LEVEL_MEMORY)
    mem.arena_init(&gameState.levelArena, levelMem)
    gameState.levelAllocator = mem.arena_allocator(&gameState.levelArena)

    gameState.playerSprite = dm.CreateSprite(dm.GetTextureAsset("ship.png"), dm.RectInt{0, 0, 64, 64})
    gameState.playerSprite.scale = 2
    gameState.playerSprite.frames = 3

    gameState.levels = LoadLevels()
    OpenLevel(START_LEVEL)

    gameState.arrowSprite = dm.CreateSprite(dm.GetTextureAsset("buildings.png"), dm.RectInt{32 * 2, 0, 32, 32})
    gameState.arrowSprite.scale = 0.4
    gameState.arrowSprite.origin = {0, 0.5}

    for &system, i in gameState.tileEnergyParticles {
        system = dm.DefaultParticleSystem

        system.texture = dm.GetTextureAsset("Energy.png")
        system.startColor = EnergyColor[EnergyType(i)]

        system.emitRate = 0

        system.startSize = 0.4

        system.color = dm.ColorOverLifetime{
            min = {1, 1, 1, 1},
            max = {1, 1, 1, 0},
            easeFun = .Cubic_Out,
        }

        system.startSpeed = 0.5

        dm.InitParticleSystem(&system)
    }

    gameState.playerMoveParticles = dm.DefaultParticleSystem
    gameState.playerMoveParticles.texture = dm.GetTextureAsset("StarParticle.png")
    gameState.playerMoveParticles.emitRate = 20
    gameState.playerMoveParticles.startSize = dm.RandomFloat{0.2, 0.5}
    gameState.playerMoveParticles.lifetime = dm.RandomFloat{0.6, 1}
    gameState.playerMoveParticles.color = dm.ColorOverLifetime{{1, 1, 1, 1}, {1, 1, 1, 0}, .Exponential_Out}

    gameState.stage = STARTING_STAGE
}

@(export)
GameUpdate : dm.GameUpdate : proc(state: rawptr) {
    gameState = cast(^GameState) state

    switch gameState.stage {
        case .MainMenu: MenuUpdate()
        case .Gameplay: GameplayUpdate()
    }
}

@(export)
GameUpdateDebug : dm.GameUpdateDebug : proc(state: rawptr, debug: bool) {
    gameState = cast(^GameState) state

    if debug {
        if dm.muiBeginWindow(dm.mui, "Config", {10, 200, 150, 100}) {
            dm.muiToggle(dm.mui, "TILE_OVERLAY", &DEBUG_TILE_OVERLAY)

            dm.muiEndWindow(dm.mui)
        }
    }
}

@(export)
GameRender : dm.GameRender : proc(state: rawptr) {
    gameState = cast(^GameState) state
    dm.ClearColor({0.1, 0.1, 0.3, 1})


    switch gameState.stage {
        case .MainMenu: MenuRender()
        case .Gameplay: GameplayRender()
    }
}
