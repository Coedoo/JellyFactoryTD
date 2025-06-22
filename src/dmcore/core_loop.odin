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

    frameUICtx: UIContext,
    tickUICtx:  UIContext,

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
    InitUI(&platformPtr.frameUICtx)
    InitUI(&platformPtr.tickUICtx)


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
    // uiCtx     = &platformPtr.uiCtx
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
    uiCtx = &platform.frameUICtx
    UIBegin(int(renderCtx.frameSize.x), int(renderCtx.frameSize.y))

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

    // fmt.println(numTicks)

    when ODIN_DEBUG {
        DebugWindow(platform)
        if platform.gameCode.gameUpdateDebug != nil {
            platform.gameCode.gameUpdateDebug(platform.gameState)
        }
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

            uiCtx = &platform.tickUICtx
            UIBegin(int(renderCtx.frameSize.x), int(renderCtx.frameSize.y))

            mui = &platform.tickMui

            platform.time.deltaTime = DELTA
            platform.gameCode.gameUpdate(platform.gameState)

            platform.tickInput.runesCount = 0

            for &state in platform.tickInput.key {
                state -= { .JustPressed, .JustReleased }
            }

            for &state in platform.tickInput.mouseKey {
                state -= { .JustPressed, .JustReleased }
            }

            platform.tickInput.scrollX = 0
            platform.tickInput.scroll = 0
            platform.tickInput.mouseDelta = {}

            UIEnd()

            muiEnd(&platform.tickMui)

            platform.time.tickFrame += 1
        }
    }

    mui = &platform.frameMui
    input = &platform.frameInput
    uiCtx = &platform.frameUICtx

    StartFrame(platform.renderCtx)

    platform.time.deltaTime = f32(durr)
    platform.gameCode.gameRender(platform.gameState)

    UIEnd()

    muiEnd(&platform.frameMui)

    if platform.debugState == false {
        DrawUI(platform.tickUICtx,  platform.renderCtx)
        muiRender(&platform.tickMui, platform.renderCtx)
    }

    DrawUI(platform.frameUICtx, platform.renderCtx)
    muiRender(&platform.frameMui, platform.renderCtx)

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

    platform.frameInput.scrollX = 0
    platform.frameInput.scroll = 0
    platform.frameInput.mouseDelta = {}

    platform.time.renderFrame += 1
}