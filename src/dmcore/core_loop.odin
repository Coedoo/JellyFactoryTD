package dmcore

import coreTime "core:time"
import "core:math"
import "core:fmt"

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

    fmt.println("Setting state pointers")

    // for k, v in assets.assetsMap {
    //     fmt.println(k, v)
    // }
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

DELTA :: 1.0 / 30.0

@(export)
CoreUpdateAndRender :: proc(platformPtr: ^Platform) {
    // SetStatePointers(platformPtr)

    mui = &platform.frameMui
    input = &platform.frameInput
    
    muiProcessInput(&platform.frameMui, &platform.frameInput)
    muiBegin(&platform.frameMui)

    platform.time.currTime = coreTime.tick_now()
    durr := coreTime.duration_seconds(coreTime.tick_diff(platform.time.prevTime, platform.time.currTime))

    platform.time.prevTime = platform.time.currTime

    platform.time.accumulator += durr
    numTicks := int(math.floor(platform.time.accumulator / DELTA))
    platform.time.accumulator -= f64(numTicks) * DELTA

    when ODIN_DEBUG {
        DebugWindow(platform)
    }

    // fmt.println(platform.time.deltaTime, platform.time.accumulator, numTicks)
    // fmt.println(durr)
    if numTicks > 0 {
        // tick_input.cursor_delta /= f32(num_ticks)
        // tick_input.scroll_delta /= f32(num_ticks)
        input = &platform.tickInput

        platform.tickInput.scrollX /= numTicks
        platform.tickInput.scroll /= numTicks
        platform.tickInput.mouseDelta /= i32(numTicks)

        for tIdx in 0 ..< numTicks {

            muiProcessInput(&platform.tickMui, &platform.tickInput)
            muiBegin(&platform.tickMui)

            // runtime.mem_copy_non_overlapping(&prev_game, &game, size_of(Game))
            // game_tick(&game, prev_game, tick_input, DELTA)

            // Clear temporary flags
            // for &flags in tick_input.keys do flags &= {.Down}
            // for &flags in tick_input.mouse_buttons do flags &= {.Down}
            if platform.pauseGame == false || platform.moveOneFrame {
                platform.time.deltaTime = DELTA
                mui = &platform.tickMui
                // fmt.println(mui)
                // fmt.printf("%p\n", mui)
                platform.gameCode.gameUpdate(platform.gameState)

                when ODIN_DEBUG {
                    if platform.gameCode.gameUpdateDebug != nil {
                        platform.gameCode.gameUpdateDebug(platform.gameState, platform.debugState)
                    }
                }

                platform.tickInput.runesCount = 0


                for &state in platform.tickInput.key {
                    // platform.tickInput.prev[key] = state
                    state -= { .JustPressed, .JustReleased }
                }

                for &state in platform.tickInput.mouseKey {
                    // platform.tickInput.mousePrev[i] = platform.input.mouseCurr[i]
                    state -= { .JustPressed, .JustReleased }
                }
            }


            platform.tickInput.scrollX = 0;
            platform.tickInput.scroll = 0;
            platform.tickInput.mouseDelta = {}

            // platform.tickInput = {}

            muiEnd(&platform.tickMui)
        }


        // Now clear the rest of the input state
        // tick_input.cursor_delta = {}
        // tick_input.scroll_delta = {}
    }

    // alpha = platform.timeaccumulator / DELTA

    // game_draw(game, prev_game, alpha)
    mui = &platform.frameMui
    input = &platform.frameInput

    StartFrame(platform.renderCtx)

    platform.time.deltaTime = f32(durr)
    platform.gameCode.gameRender(platform.gameState)

    muiEnd(&platform.frameMui)

    // platform.frameInput = {}

    muiRender(&platform.tickMui, platform.renderCtx)
    muiRender(&platform.frameMui, platform.renderCtx)

    FlushCommands(platform.renderCtx)

    DrawPrimitiveBatch(platform.renderCtx, &platform.renderCtx.debugBatch)
    DrawPrimitiveBatch(platform.renderCtx, &platform.renderCtx.debugBatchScreen)

    EndFrame(platform.renderCtx)

    for &state in platform.frameInput.key {
        // platform.frameInput.prev[key] = state
        state -= { .JustPressed, .JustReleased }
    }

    for &state in platform.frameInput.mouseKey {
        // platform.frameInput.mousePrev[i] = platform.input.mouseCurr[i]
        state -= { .JustPressed, .JustReleased }
    }
}