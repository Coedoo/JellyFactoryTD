package dmcore

import coreTime "core:time"
import "core:math"
import "core:fmt"

import "core:dynlib"
import "core:os"

// foreign import "odin_env"

input: ^Input
time: ^TimeData
renderCtx: ^RenderContext
audio: ^Audio
mui: ^Mui
assets: ^Assets
uiCtx: ^UIContext

platform: ^Platform

Platform :: struct {
    gameCode: GameCode,

    tickMui:   Mui,
    frameMui:  Mui,

    tickInput:  Input,
    frameInput: Input,

    time:      TimeData,
    renderCtx: ^RenderContext,
    assets:    Assets,
    audio:     Audio,
    uiCtx:     UIContext,

    gameState: rawptr,

    debugState: bool,
    pauseGame: bool,
    moveOneFrame: bool,

    SetWindowSize: proc(width, height: int),
}

InitPlatform :: proc(platformPtr: ^Platform) {
    InitRenderContext(platformPtr.renderCtx)

    muiInit(&platformPtr.tickMui, platformPtr.renderCtx)
    muiInit(&platformPtr.frameMui, platformPtr.renderCtx)
    InitUI(&platformPtr.uiCtx)


    InitAudio(&platformPtr.audio)

    TimeInit(&platformPtr.time)

    UpdateStatePointers(platformPtr)
}

@(export)
UpdateStatePointers : UpdateStatePointerFunc : proc(platformPtr: ^Platform) {
    platform = platformPtr

    // input     = &platformPtr.input
    time      = &platformPtr.time
    renderCtx = platformPtr.renderCtx
    audio     = &platformPtr.audio
    // mui       = platformPtr.mui
    assets    = &platformPtr.assets
    uiCtx     = &platformPtr.uiCtx
}

when ODIN_OS == .Windows {
    GameCodeBackend :: struct {
        lib: dynlib.Library,
        lastWriteTime: os.File_Time,
    }
}
else {
    GameCodeBackend :: struct {}
}

GameCode :: struct {
    using backend: GameCodeBackend,

    setStatePointers: UpdateStatePointerFunc,

    preGameLoad:     PreGameLoad,
    gameHotReloaded: GameHotReloaded,
    gameLoad:        GameLoad,
    gameUpdate:      GameUpdate,
    gameUpdateDebug: GameUpdateDebug,
    gameRender:      GameRender,
    updateAndRender: proc(platform: ^Platform)
}

DELTA :: 1.0 / 60.0

// _tick_now_ :: proc "contextless" () -> f32 {
//     foreign odin_env {
//         tick_now :: proc "contextless" () -> f32 ---
//     }
//     return tick_now()
// }


@(export)
CoreUpdateAndRender :: proc(platformPtr: ^Platform) {
    mui = &platform.frameMui
    input = &platform.frameInput

    muiProcessInput(&platform.frameMui, &platform.frameInput)
    muiBegin(&platform.frameMui)

    platform.time.currTime = coreTime.tick_now()
    durrTick := coreTime.tick_diff(platform.time.prevTime, platform.time.currTime)
    durr := coreTime.duration_seconds(durrTick)


    if platform.pauseGame == false {
        platform.time.gameTickTime += durrTick
        platform.time.gameTime = coreTime.duration_seconds(platform.time.gameTickTime)
    }

    platform.time.realTime = coreTime.duration_seconds(
        coreTime.tick_diff(
            platform.time.startTime,
            platform.time.currTime
        )
    )

    platform.time.prevTime = platform.time.currTime

    platform.time.accumulator += durr
    numTicks := int(math.floor(platform.time.accumulator / DELTA))
    platform.time.accumulator -= f64(numTicks) * DELTA



    when ODIN_DEBUG {
        DebugWindow(platform)
    }

    if platform.pauseGame {
        numTicks = 0
    }

    if platform.moveOneFrame {
        numTicks = max(1, numTicks)
        platform.moveOneFrame = false
    }

    // fmt.println("delta:", platform.time.deltaTime, "\n", "acc:", platform.time.accumulator, "\n", "ticks:", numTicks)
    // fmt.println(durr)
    if numTicks > 0 {
        input = &platform.tickInput

        platform.tickInput.scrollX /= numTicks
        platform.tickInput.scroll /= numTicks
        platform.tickInput.mouseDelta /= i32(numTicks)

        for tIdx in 0 ..< numTicks {
            muiProcessInput(&platform.tickMui, &platform.tickInput)
            muiBegin(&platform.tickMui)

            UIBegin(int(renderCtx.frameSize.x), int(renderCtx.frameSize.y))

            mui = &platform.tickMui

            platform.time.deltaTime = DELTA
            platform.gameCode.gameUpdate(platform.gameState)

            when ODIN_DEBUG {
                if platform.gameCode.gameUpdateDebug != nil {
                    platform.gameCode.gameUpdateDebug(platform.gameState, platform.debugState)
                }
            }

            platform.tickInput.runesCount = 0

            for &state in platform.tickInput.key {
                state -= { .JustPressed, .JustReleased }
            }

            for &state in platform.tickInput.mouseKey {
                state -= { .JustPressed, .JustReleased }
            }

            platform.tickInput.scrollX = 0;
            platform.tickInput.scroll = 0;
            platform.tickInput.mouseDelta = {}

            UIEnd()

            muiEnd(&platform.tickMui)
        }
    }

    mui = &platform.frameMui
    input = &platform.frameInput

    StartFrame(platform.renderCtx)

    platform.time.deltaTime = f32(durr)
    platform.gameCode.gameRender(platform.gameState)

    muiEnd(&platform.frameMui)

    muiRender(&platform.tickMui, platform.renderCtx)
    muiRender(&platform.frameMui, platform.renderCtx)

    DrawUI(platform.renderCtx)

    // FlushCommands(platform.renderCtx)

    DrawPrimitiveBatch(platform.renderCtx, &platform.renderCtx.debugBatch)
    DrawPrimitiveBatch(platform.renderCtx, &platform.renderCtx.debugBatchScreen)

    EndFrame(platform.renderCtx)

    for &state in platform.frameInput.key {
        state -= { .JustPressed, .JustReleased }
    }

    for &state in platform.frameInput.mouseKey {
        state -= { .JustPressed, .JustReleased }
    }

    platform.frameInput.scrollX = 0;
    platform.frameInput.scroll = 0;
    platform.frameInput.mouseDelta = {}
}