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
    nowLoading: ^dm.AssetData,
    loadingIndex: int,
}

SetWindowSize :: proc(width, height: int) {

}

FileLoadedCallback :: proc(data: []u8) {
    assert(data != nil)

    asset := engineData.assets.toLoad[assetsLoadingState.loadingIndex]

    switch desc in asset.descriptor {
    case dm.TextureAssetDescriptor:
        asset.handle = cast(dm.Handle) dm.LoadTextureFromMemoryCtx(engineData.renderCtx, data, desc.filter)
        // delete(data)

    case dm.ShaderAssetDescriptor:
        str := strings.string_from_ptr(raw_data(data), len(data))
        asset.handle = cast(dm.Handle) dm.CompileShaderSource(engineData.renderCtx, str)
        // delete(data)

    case dm.FontAssetDescriptor:
        panic("FIX SUPPORT OF FONT ASSET LOADING")

    case dm.RawFileAssetDescriptor:
        asset.fileData = data

    case dm.SoundAssetDescriptor:
        asset.handle = cast(dm.Handle) dm.LoadSoundFromMemoryCtx(&engineData.audio, data)
        // delete(data)
    }

    // assetsLoadingState.nowLoading = assetsLoadingState.nowLoading.next
    assetsLoadingState.loadedCount += 1
    assetsLoadingState.loadingIndex += 1

    if assetsLoadingState.loadingIndex < assetsLoadingState.maxCount {
        assetsLoadingState.nowLoading = engineData.assets.toLoad[assetsLoadingState.loadingIndex]
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
    gl.SetCurrentContextById("game_viewport")

    InitInput()

    //////////////

    engineData.renderCtx = dm.CreateRenderContextBackend()
    dm.InitRenderContext(engineData.renderCtx)
    engineData.mui = dm.muiInit(engineData.renderCtx)
    dm.InitUI(&engineData.uiCtx, engineData.renderCtx)

    dm.InitAudio(&engineData.audio)
    dm.TimeInit(&engineData)

    engineData.SetWindowSize = SetWindowSize

    ////////////

    dm.UpdateStatePointer(&engineData)
    game.PreGameLoad(&engineData.assets)

    assetsLoadingState.maxCount = len(engineData.assets.assetsMap)
    if(assetsLoadingState.maxCount > 0) {
        assetsLoadingState.nowLoading = engineData.assets.toLoad[0]
    }

    LoadNextAsset()
}

@(export, link_name="step")
step :: proc (delta: f32) -> bool {
    free_all(context.temp_allocator)
    ////////

    @static gameLoaded: bool
    if assetsLoadingState.finishedLoading == false {
        // if assetsLoadingState.nowLoading != nil {
        //     dm.DrawTextCentered(engineData.renderCtx, fmt.tprint("Loading:", assetsLoadingState.nowLoading.fileName),
        //         dm.LoadDefaultFont(engineData.renderCtx), dm.ToV2(engineData.renderCtx.frameSize) / 2)
        //     dm.FlushCommands(engineData.renderCtx)
        // }
        return true
    }
    else if gameLoaded == false {
        gameLoaded = true

        fmt.println("LOADING GAME")
        
        game.GameLoad(&engineData)
    }

    dm.TimeUpdate(&engineData)

    for key, state in engineData.input.curr {
        engineData.input.prev[key] = state
    }

    for mouseBtn, i in engineData.input.mouseCurr {
        engineData.input.mousePrev[i] = engineData.input.mouseCurr[i]
    }

    engineData.input.runesCount = 0
    engineData.input.scrollX = 0;
    engineData.input.scroll = 0;

    for i in 0..<eventBufferOffset {
        e := &eventsBuffer[i]
        // fmt.println(e)
        #partial switch e.kind {
            case .Mouse_Down:
                idx := clamp(int(e.mouse.button), 0, len(JsToDMMouseButton))
                btn := JsToDMMouseButton[idx]

                engineData.input.mouseCurr[btn] = .Down

            case .Mouse_Up:
                idx := clamp(int(e.mouse.button), 0, len(JsToDMMouseButton))
                btn := JsToDMMouseButton[idx]

                engineData.input.mouseCurr[btn] = .Up

            case .Mouse_Move: 
                engineData.input.mousePos.x = i32(e.mouse.client.x)
                engineData.input.mousePos.y = i32(e.mouse.client.y)

                engineData.input.mouseDelta.x = i32(e.mouse.movement.x)
                engineData.input.mouseDelta.y = i32(e.mouse.movement.y)

            case .Key_Up:
                // fmt.println()
                c := string(e.key._code_buf[:e.key._code_len])
                key := JsKeyToKey[c]
                engineData.input.curr[key] = .Up

            case .Key_Down:
                c := string(e.key._code_buf[:e.key._code_len])
                key := JsKeyToKey[c]
                engineData.input.curr[key] = .Down
        }

    }
    eventBufferOffset = 0

    /////////


    dm.muiProcessInput(engineData.mui, &engineData.input)
    dm.muiBegin(engineData.mui)

    dm.UpdateStatePointer(&engineData)
    // dm.UIBegin(dm.uiCtx,
    //            int(engineData.renderCtx.frameSize.x),
    //            int(engineData.renderCtx.frameSize.y))

    when ODIN_DEBUG {
        if dm.GetKeyStateCtx(&engineData.input, .U) == .JustPressed {
            engineData.debugState = !engineData.debugState
            engineData.pauseGame = engineData.debugState

            if engineData.debugState {
                dm.muiShowWindow(engineData.mui, "Debug")
            }
        }

        if engineData.debugState && dm.muiBeginWindow(engineData.mui, "Debug", {0, 0, 100, 240}, nil) {
            // dm.muiLabel(mui, "Time:", time.time)
            dm.muiLabel(engineData.mui, "GameTime:", engineData.time.gameTime)

            dm.muiLabel(engineData.mui, "Frame:", engineData.time.frame)

            if dm.muiButton(engineData.mui, "Play" if engineData.pauseGame else "Pause") {
                engineData.pauseGame = !engineData.pauseGame
            }

            if dm.muiButton(engineData.mui, ">") {
                engineData.moveOneFrame = true
            }

            dm.muiEndWindow(engineData.mui)
        }
    }


    if engineData.pauseGame == false || engineData.moveOneFrame {
        game.GameUpdate(engineData.gameState)
    }

    when ODIN_DEBUG {
        game.GameUpdateDebug(engineData.gameState, engineData.debugState)
    }

    game.GameRender(engineData.gameState)

    // dm.UIEnd()
    dm.DrawUI(engineData.renderCtx)

    dm.FlushCommands(engineData.renderCtx)
    // DrawPrimitiveBatch(cast(^renderer.RenderContext_d3d) renderCtx)
    // renderCtx.debugBatch.index = 0

    dm.muiEnd(engineData.mui)
    dm.muiRender(engineData.mui, engineData.renderCtx)

    return true
}