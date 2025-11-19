package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"
import "core:mem"

import "../ldtk"

import "core:os"
import "core:encoding/json"

import sa "core:container/small_array"

v2 :: dm.v2
iv2 :: dm.iv2

GameStage :: enum {
    MainMenu,
    Gameplay,

    Editor,
}

GameState :: struct {
    stage: GameStage,
    menuStage: MenuStage,

    levelArena: mem.Arena,
    levelAllocator: mem.Allocator,

    levels: []Level,
    loadedLevel: ^Level, // currentLevel

    editorState: EditorState,

    masterVolume: f32,
    musicVolume: f32,
    sfxVolume: f32,

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
        buildingPipeDirs: sa.Small_Array(6, DirectionSet),

        levelFullySpawned: bool,
        nextWaveIdx: int,
        wavesState: sa.Small_Array(MAX_WAVES, WaveState),


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

    startCoordWasEmpty: bool,
    startCoordNeighbords: DirectionSet,
    // startCoordHadBuildingNearby: bool,
    prevPrevCoord: iv2,
    prevCoord: iv2,

    // DEBUG
    debugDrawPathGraph: bool,
    debugDrawGrid: bool,
    debugDrawPathsBetweenBuildings: bool,
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

MousePosGrid :: proc(camera := dm.renderCtx.camera) -> (gridPos: iv2) {
    mousePos := dm.ScreenToWorldSpace(camera, dm.input.mousePos)

    gridPos.x = i32(mousePos.x)
    gridPos.y = i32(mousePos.y)

    return
}

@export
PreGameLoad : dm.PreGameLoad : proc(assets: ^dm.Assets) {
    // dm.RegisterAsset("testTex.png", dm.TextureAssetDescriptor{})

    // dm.RegisterAsset("level1.ldtk", dm.RawFileAssetDescriptor{})
    dm.RegisterAsset("kenney_tilemap.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("buildings.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("turret_test_4.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("Energy.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("StarParticle.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("Jelly_.png", dm.TextureAssetDescriptor{})

    dm.RegisterAsset("ship.png", dm.TextureAssetDescriptor{})
    
    // dm.RegisterAsset("menu/JellyBackground.png", dm.TextureAssetDescriptor{filter = .Bilinear})
    // dm.RegisterAsset("menu/JellyShip.png", dm.TextureAssetDescriptor{filter = .Bilinear})
    // dm.RegisterAsset("menu/Tower1.png", dm.TextureAssetDescriptor{filter = .Bilinear})
    // dm.RegisterAsset("menu/Tower2.png", dm.TextureAssetDescriptor{filter = .Bilinear})
    // dm.RegisterAsset("menu/BackgroundBullet1.png", dm.TextureAssetDescriptor{filter = .Bilinear})
    // dm.RegisterAsset("menu/Crossfire.png", dm.TextureAssetDescriptor{filter = .Bilinear})

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

    // @TODO @REWRITE
    Tileset.atlas.texture = dm.GetTextureAsset(Tileset.atlas.texAssetPath)

    if gameState.loadedLevel == nil {
        data, ok := os.read_entire_file("test_save.json")
        // @TODO @Allocation
        gameState.loadedLevel = new(Level)
        if ok {
            err := json.unmarshal(data, gameState.loadedLevel)

            OpenLevel(gameState.loadedLevel)
        }
        else {
            if gameState.loadedLevel.sizeX == 0 || gameState.loadedLevel.sizeY == 0 {
                InitNewLevel(gameState.loadedLevel, 32, 32)
            }

            OpenLevel(gameState.loadedLevel)
        }
    }

    gameState.money = 10000

    when ODIN_DEBUG {
        gameState.debugDrawGrid = true
    }

}

@(export)
GameUpdate : dm.GameUpdate : proc(state: rawptr) {
    gameState = cast(^GameState) state
    switch gameState.stage {
        case .MainMenu: MenuUpdate()
        case .Gameplay: GameplayUpdate()

        case .Editor: EditorUpdate(&gameState.editorState)
    }
}

@(export)
GameUpdateDebug : dm.GameUpdateDebug : proc(state: rawptr) {
    gameState = cast(^GameState) state
    if dm.GetKeyState(.Tilde) == .JustPressed {
        dm.platform.debugState = !dm.platform.debugState
        dm.platform.pauseGame = dm.platform.debugState
    }

    if dm.GetKeyState(.Tab) == .JustPressed {
        if gameState.stage == .Gameplay {
            InitEditor(&gameState.editorState)

            gameState.stage = .Editor

        }
        else if gameState.stage == .Editor {
            CloseEditor(&gameState.editorState)

            gameState.stage = .Gameplay
        }
    }

    if dm.platform.debugState {
        if dm.muiBeginWindow(dm.mui, "Debug menu", {400, 10, 210, 250}) {
            dm.muiToggle(dm.mui, "Draw grid", &gameState.debugDrawGrid)
            dm.muiToggle(dm.mui, "Draw path graph", &gameState.debugDrawPathGraph)
            dm.muiToggle(dm.mui, "Draw energy paths", &gameState.debugDrawPathsBetweenBuildings)

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

        case .Editor: EditorRender(gameState.editorState)
    }

    // DrawSequence(&TestSequence)
}
