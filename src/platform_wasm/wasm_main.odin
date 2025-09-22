package platform_wasm

import "base:runtime"
import "core:fmt"

import "core:mem"
import "core:strings"

import dm "../dmcore"
import gl "vendor:wasm/WebGL"

import "core:sys/wasm/js"

import coreTime "core:time"

import game "../game"

engineData: dm.Platform

assetsLoadingState: struct {
    maxCount: int,
    loadedCount: int,

    finishedLoading: bool,
    // nowLoading: string,
    // loadingIndex: int,
}

foreign import wasmUtilities "utility"
foreign wasmUtilities {
    SetCanvasSize :: proc "c" (width, height: int) ---
}

SetWindowSize :: proc(width, height: int) {
    engineData.renderCtx.frameSize.x = i32(width)
    engineData.renderCtx.frameSize.y = i32(height)

    SetCanvasSize(width, height)

    dm.ResizeFramebuffer(engineData.renderCtx, engineData.renderCtx.ppFramebufferSrc)
    dm.ResizeFramebuffer(engineData.renderCtx, engineData.renderCtx.ppFramebufferDest)
}

FileLoadedCallback :: proc(data: []u8, key: string) {
    assert(data != nil)

    // queueEntry := engineData.assets.loadQueue[assetsLoadingState.loadingIndex]
    asset := &engineData.assets.assetsMap[key]

    switch desc in asset.descriptor {
    case dm.TextureAssetDescriptor:
        asset.handle = cast(dm.Handle) dm.LoadTextureFromMemoryCtx(engineData.renderCtx, data, desc.filter)
        delete(data)

    case dm.ShaderAssetDescriptor:
        str := strings.string_from_ptr(raw_data(data), len(data))
        asset.handle = cast(dm.Handle) dm.CompileShaderSource(engineData.renderCtx, asset.fileName, str)
        // delete(data)

    case dm.FontAssetDescriptor:
        // panic("FIX SUPPORT OF FONT ASSET LOADING")
        asset.handle = dm.LoadFontSDF(engineData.renderCtx, data, desc.fontSize)

    case dm.RawFileAssetDescriptor:
        asset.fileData = data

    case dm.SoundAssetDescriptor:
        asset.handle = cast(dm.Handle) dm.LoadSoundFromMemory(data)
        // delete(data)
    }

    assetsLoadingState.loadedCount += 1
    if(assetsLoadingState.loadedCount >= assetsLoadingState.maxCount) {
        assetsLoadingState.finishedLoading = true
    }
}

main :: proc() {
    gl.SetCurrentContextById("game_viewport")

    InitInput()

    //////////////

    engineData.renderCtx = dm.CreateRenderContextBackend()
    dm.InitPlatform(&engineData)
    // dm.InitRenderContext(engineData.renderCtx)
    // engineData.mui = dm.muiInit(engineData.renderCtx)
    // dm.InitUI(&engineData.uiCtx, engineData.renderCtx)

    // dm.InitAudio(&engineData.audio)
    // dm.TimeInit(&engineData)

    engineData.SetWindowSize = SetWindowSize

    engineData.gameCode.updateAndRender = dm.CoreUpdateAndRender
    engineData.gameCode.gameUpdate = game.GameUpdate
    engineData.gameCode.gameUpdateDebug = game.GameUpdateDebug
    engineData.gameCode.gameRender = game.GameRender


    ////////////

    dm.UpdateStatePointers(&engineData)
    game.PreGameLoad(&engineData.assets)

    assetsLoadingState.maxCount = len(engineData.assets.assetsMap)
    // if(assetsLoadingState.maxCount > 0) {
    //     assetsLoadingState.nowLoading = engineData.assets.loadQueue[0].name
    // }

    for &state in engineData.frameInput.key {
        state += {.Up}
    }
    for &state in engineData.tickInput.key {
        state += {.Up}
    }

    // LoadNextAsset()
    for asset in engineData.assets.loadQueue {
        path := strings.concatenate({dm.ASSETS_ROOT, asset.name}, context.temp_allocator)
        LoadFile(path, asset.key, FileLoadedCallback)
    }
}

@(export, link_name="step")
step :: proc (delta: f32) -> bool {
    ////////

    @static gameLoaded: bool
    if assetsLoadingState.finishedLoading == false {
        // if assetsLoadingState.nowLoading != "" {
            dm.ClearColor({0.1, 0.1, 0.1, 1})
            dm.BeginScreenSpace()

            pos := dm.ToV2(engineData.renderCtx.frameSize)
            pos.x /= 2
            pos.y -= 80
            dm.DrawTextCentered(
                "Loading...",
                pos
            )
            // dm.DrawTextCentered(
            //     fmt.tprintf("Loading: %v [%v/%v]", 
            //         assetsLoadingState.nowLoading, 
            //         assetsLoadingState.loadedCount + 1, 
            //         assetsLoadingState.maxCount
            //     ),
            //     pos
            // )

            dm.EndScreenSpace()
            // dm.FlushCommands(engineData.renderCtx)
        // }
        return true
    }
    else if gameLoaded == false {
        gameLoaded = true

        fmt.println("LOADING GAME")
        
        game.GameLoad(&engineData)
    }

    free_all(context.temp_allocator)
    dm.TimeUpdate(&engineData)

    // for key, state in engineData.input.curr {
    //     engineData.input.prev[key] = state
    // }

    // for mouseBtn, i in engineData.input.mouseCurr {
    //     engineData.input.mousePrev[i] = engineData.input.mouseCurr[i]
    // }

    // engineData.input.runesCount = 0
    // engineData.input.scrollX = 0;
    // engineData.input.scroll = 0;

    for i in 0..<eventBufferOffset {
        e := &eventsBuffer[i]
        // fmt.println(e)

        #partial switch e.kind {
            case .Mouse_Down:
                idx := clamp(int(e.mouse.button), 0, len(JsToDMMouseButton))
                btn := JsToDMMouseButton[idx]

                // engineData.frameInput.mouseCurr[btn] = .Down
                engineData.tickInput.mouseKey[btn] -= { .Up }
                engineData.tickInput.mouseKey[btn] += { .Down, .JustPressed }

                engineData.frameInput.mouseKey[btn] -= { .Up }
                engineData.frameInput.mouseKey[btn] += { .Down, .JustPressed }

            case .Mouse_Up:
                idx := clamp(int(e.mouse.button), 0, len(JsToDMMouseButton))
                btn := JsToDMMouseButton[idx]

                // engineData.frameInput.mouseCurr[btn] = .Up
                engineData.tickInput.mouseKey[btn] -= { .Down }
                engineData.tickInput.mouseKey[btn] += { .Up, .JustReleased }

                engineData.frameInput.mouseKey[btn] -= { .Down }
                engineData.frameInput.mouseKey[btn] += { .Up, .JustReleased }

            case .Mouse_Move: 
                // fmt.println(e.mouse.offset)

                canvasRect := js.get_bounding_client_rect("game_viewport")

                engineData.frameInput.mousePos.x = i32(e.mouse.client.x - i64(canvasRect.x))
                engineData.frameInput.mousePos.y = i32(e.mouse.client.y - i64(canvasRect.y))

                engineData.frameInput.mouseDelta.x = i32(e.mouse.movement.x)
                engineData.frameInput.mouseDelta.y = i32(e.mouse.movement.y)

                engineData.tickInput.mouseDelta = engineData.frameInput.mouseDelta
                engineData.tickInput.mousePos = engineData.frameInput.mousePos

            case .Key_Up:
                // fmt.println()
                c := string(e.key._code_buf[:e.key._code_len])
                key := JsKeyToKey[c]
                // engineData.frameInput.curr[key] = .Up

                if .Down in engineData.tickInput.key[key] {
                    engineData.tickInput.key[key] -= { .Down }
                    engineData.tickInput.key[key] += { .Up, .JustReleased }
                }

                if .Down in engineData.frameInput.key[key] {
                    engineData.frameInput.key[key] -= { .Down }
                    engineData.frameInput.key[key] += { .Up, .JustReleased }
                }

            case .Key_Down:
                c := string(e.key._code_buf[:e.key._code_len])
                key := JsKeyToKey[c]
                // engineData.frameInput.curr[key] = .Down

                if .Up in engineData.tickInput.key[key] {
                    engineData.tickInput.key[key] -= { .Up }
                    engineData.tickInput.key[key] += { .Down, .JustPressed }
                }

                if .Up in engineData.frameInput.key[key] {
                    engineData.frameInput.key[key] -= { .Up }
                    engineData.frameInput.key[key] += { .Down, .JustPressed }
                }


            case .Wheel:
                engineData.frameInput.scroll  = -int(e.wheel.delta[1] / 100)
                engineData.frameInput.scrollX = int(e.wheel.delta[0] / 100)

                engineData.tickInput.scroll  = engineData.frameInput.scroll
                engineData.tickInput.scrollX = engineData.frameInput.scrollX

                // fmt.println(engineData.frameInput.scroll)
        }

    }

    eventBufferOffset = 0

    engineData.gameCode.updateAndRender(&engineData)

    return true
}