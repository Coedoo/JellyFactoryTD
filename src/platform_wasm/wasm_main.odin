package platform_wasm

import "core:runtime"
import "core:fmt"

import "core:mem"
import "core:strings"

import dm "../dmcore"
import gl "vendor:wasm/WebGL"

import "vendor:wasm/js"

import coreTime "core:time"

import game "../../examples/Arkanoid/src"
// import game "../game"

platform: dm.Platform

assetsLoadingState: struct {
    maxCount: int,
    loadedCount: int,

    finishedLoading: bool,
    nowLoading: ^dm.AssetData,
    loadingIndex: int,
}

FileLoadedCallback :: proc(data: []u8) {
    assert(data != nil)

    asset := platform.assets.toLoad[assetsLoadingState.loadingIndex]

    switch desc in asset.descriptor {
    case dm.TextureAssetDescriptor:
        asset.handle = cast(dm.Handle) dm.LoadTextureFromMemoryCtx(platform.renderCtx, data, desc.filter)
        // delete(data)

    case dm.ShaderAssetDescriptor:
        str := strings.string_from_ptr(raw_data(data), len(data))
        asset.handle = cast(dm.Handle) dm.CompileShaderSource(platform.renderCtx, str)
        // delete(data)

    case dm.FontAssetDescriptor:
        panic("FIX SUPPORT OF FONT ASSET LOADING")

    case dm.RawFileAssetDescriptor:
        asset.fileData = data

    case dm.SoundAssetDescriptor:
        asset.handle = cast(dm.Handle) dm.LoadSoundFromMemoryCtx(&platform.audio, data)
        // delete(data)
    }

    // assetsLoadingState.nowLoading = assetsLoadingState.nowLoading.next
    assetsLoadingState.loadedCount += 1
    assetsLoadingState.loadingIndex += 1

    if assetsLoadingState.loadingIndex < assetsLoadingState.maxCount {
        assetsLoadingState.nowLoading = platform.assets.toLoad[assetsLoadingState.loadingIndex]
    }
    else {
        assetsLoadingState.nowLoading = nil
    }

    LoadNextAsset()
}

LoadNextAsset :: proc() {
    if assetsLoadingState.nowLoading == nil {
        assetsLoadingState.finishedLoading = true
        fmt.println("Finished Loading Assets")
        return
    }

    if assetsLoadingState.nowLoading.descriptor == nil {
        assetsLoadingState.nowLoading = assetsLoadingState.nowLoading.next
        assetsLoadingState.loadedCount += 1

        fmt.println("Incorrect descriptor. Skipping")
    }

    path := strings.concatenate({dm.ASSETS_ROOT, assetsLoadingState.nowLoading.fileName}, context.temp_allocator)
    LoadFile(path, FileLoadedCallback)

    fmt.println("[", assetsLoadingState.loadedCount + 1, "/", assetsLoadingState.maxCount, "]",
                 " Loading asset: ", assetsLoadingState.nowLoading.fileName, sep = "")
}

main :: proc() {
    InitContext()

    context = wasmContext

    gl.SetCurrentContextById("game_viewport")

    InitInput()

    //////////////

    platform.renderCtx = new(dm.RenderContext)
    dm.InitRenderContext(platform.renderCtx)
    platform.mui = dm.muiInit(platform.renderCtx)

    dm.InitAudio(&platform.audio)
    dm.TimeInit(&platform)

    ////////////

    dm.UpdateStatePointer(&platform)
    game.PreGameLoad(&platform.assets)

    assetsLoadingState.maxCount = len(platform.assets.assetsMap)
    if(assetsLoadingState.maxCount > 0) {
        assetsLoadingState.nowLoading = platform.assets.toLoad[0]
    }

    LoadNextAsset()
}

@(export, link_name="step")
step :: proc "contextless" (delta: f32, ctx: ^runtime.Context) {
    context = wasmContext
    free_all(context.temp_allocator)

    ////////

    @static gameLoaded: bool
    if assetsLoadingState.finishedLoading == false {
        // if assetsLoadingState.nowLoading != nil {
        //     dm.DrawTextCentered(platform.renderCtx, fmt.tprint("Loading:", assetsLoadingState.nowLoading.fileName),
        //         dm.LoadDefaultFont(platform.renderCtx), dm.ToV2(platform.renderCtx.frameSize) / 2)
        //     dm.FlushCommands(platform.renderCtx)
        // }
        return
    }
    else if gameLoaded == false {
        gameLoaded = true
        game.GameLoad(&platform)
    }

    using platform

    dm.TimeUpdate(&platform)

    for key, state in input.curr {
        input.prev[key] = state
    }

    for mouseBtn, i in input.mouseCurr {
        input.mousePrev[i] = input.mouseCurr[i]
    }

    input.runesCount = 0
    input.scrollX = 0;
    input.scroll = 0;

    for i in 0..<eventBufferOffset {
        e := &eventsBuffer[i]
        // fmt.println(e)
        #partial switch e.kind {
            case .Mouse_Down:
                idx := clamp(int(e.mouse.button), 0, len(JsToDMMouseButton))
                btn := JsToDMMouseButton[idx]

                platform.input.mouseCurr[btn] = .Down

            case .Mouse_Up:
                idx := clamp(int(e.mouse.button), 0, len(JsToDMMouseButton))
                btn := JsToDMMouseButton[idx]

                platform.input.mouseCurr[btn] = .Up

            case .Mouse_Move: 
                platform.input.mousePos.x = i32(e.mouse.client.x)
                platform.input.mousePos.y = i32(e.mouse.client.y)

                platform.input.mouseDelta.x = i32(e.mouse.movement.x)
                platform.input.mouseDelta.y = i32(e.mouse.movement.y)

            case .Key_Up:
                // fmt.println()
                c := string(e.key._code_buf[:e.key._code_len])
                key := JsKeyToKey[c]
                input.curr[key] = .Up

            case .Key_Down:
                c := string(e.key._code_buf[:e.key._code_len])
                key := JsKeyToKey[c]
                input.curr[key] = .Down
        }

    }
    eventBufferOffset = 0

    /////////


    dm.muiProcessInput(mui, &input)
    dm.muiBegin(mui)

    when ODIN_DEBUG {
        if dm.GetKeyStateCtx(&input, .U) == .JustPressed {
            debugState = !debugState
            pauseGame = debugState

            if debugState {
                dm.muiShowWindow(mui, "Debug")
            }
        }

        if debugState && dm.muiBeginWindow(mui, "Debug", {0, 0, 100, 240}, nil) {
            // dm.muiLabel(mui, "Time:", time.time)
            dm.muiLabel(mui, "GameTime:", time.gameTime)

            dm.muiLabel(mui, "Frame:", time.frame)

            if dm.muiButton(mui, "Play" if pauseGame else "Pause") {
                pauseGame = !pauseGame
            }

            if dm.muiButton(mui, ">") {
                moveOneFrame = true
            }

            dm.muiEndWindow(mui)
        }
    }


    if pauseGame == false || moveOneFrame {
        game.GameUpdate(gameState)
    }

    when ODIN_DEBUG {
        game.GameUpdateDebug(gameState, debugState)
    }

    game.GameRender(gameState)

    dm.FlushCommands(renderCtx)
    // DrawPrimitiveBatch(cast(^renderer.RenderContext_d3d) renderCtx)
    // renderCtx.debugBatch.index = 0

    dm.muiEnd(mui)
    dm.muiRender(mui, renderCtx)
}