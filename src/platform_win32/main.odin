package main

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import d3d "vendor:directx/d3d_compiler"

import sdl "vendor:sdl2"

import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode/utf8"

import "core:dynlib"

import math "core:math/linalg/glsl"

import mem "core:mem/virtual"

import dm "../dmcore"

import "core:image/png"

import "core:math/rand"

window: ^sdl.Window

engineData: dm.Platform

SetWindowSize :: proc(width, height: int) {
    engineData.renderCtx.frameSize.x = i32(width)
    engineData.renderCtx.frameSize.y = i32(height)

    oldSize: dm.iv2
    sdl.GetWindowSize(window, &oldSize.x, &oldSize.y)

    delta := dm.iv2{i32(width), i32(height)} - oldSize
    delta /= 2

    pos: dm.iv2
    sdl.GetWindowPosition(window, &pos.x, &pos.y)
    sdl.SetWindowPosition(window, pos.x - delta.x, pos.y - delta.y)

    sdl.SetWindowSize(window, i32(width), i32(height))
    dm.ResizeFrambuffer(engineData.renderCtx, width, height)
}

main :: proc() {
    sdl.Init({.VIDEO, .AUDIO})
    defer sdl.Quit()

    sdl.SetHintWithPriority(sdl.HINT_RENDER_DRIVER, "direct3d11", .OVERRIDE)

    window = sdl.CreateWindow("DanMofu", sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED, 
                               dm.defaultWindowWidth, dm.defaultWindowHeight,
                               {.ALLOW_HIGHDPI, .HIDDEN})

    defer sdl.DestroyWindow(window);

    engineData.SetWindowSize = SetWindowSize

    // Init Renderer
    window_system_info: sdl.SysWMinfo

    sdl.GetVersion(&window_system_info.version)
    sdl.GetWindowWMInfo(window, &window_system_info)

    nativeWnd := dxgi.HWND(window_system_info.info.win.window)

    engineData.renderCtx = dm.CreateRenderContextBackend(nativeWnd)
    dm.InitRenderContext(engineData.renderCtx)

    // Other Init
    engineData.mui = dm.muiInit(engineData.renderCtx)
    dm.InitUI(&engineData.uiCtx, engineData.renderCtx)

    dm.InitAudio(&engineData.audio)

    dm.TimeInit(&engineData)

    context.random_generator = rand.default_random_generator()

    dm.UpdateStatePointer(&engineData)

    gameCode: GameCode
    if LoadGameCode(&gameCode, "Game.dll") == false {
        return
    }

    gameCode.setStatePointers(&engineData)

    // Assets loading!
    if gameCode.preGameLoad != nil {
        gameCode.preGameLoad(&engineData.assets)

        for name, &asset in engineData.assets.assetsMap {
            if asset.descriptor == nil {
                fmt.eprintln("Incorrect asset descriptor for asset:", name)
                continue
            }

            path := strings.concatenate({dm.ASSETS_ROOT, name}, context.temp_allocator)
            fmt.println("Loading asset at path:", path)
            data, ok := os.read_entire_file(path, context.allocator)

            if ok == false {
                fmt.eprintln("Failed to load asset file at path:", path)
                continue
            }

            writeTime, err := os.last_write_time_by_name(path)
            if err == os.ERROR_NONE {
                asset.lastWriteTime = writeTime
            }

            switch desc in asset.descriptor {
            case dm.TextureAssetDescriptor:
                asset.handle = cast(dm.Handle) dm.LoadTextureFromMemoryCtx(engineData.renderCtx, data, desc.filter)

            case dm.ShaderAssetDescriptor:
                str := strings.string_from_ptr(raw_data(data), len(data))
                asset.handle = cast(dm.Handle) dm.CompileShaderSource(engineData.renderCtx, str)

            case dm.FontAssetDescriptor:
                panic("FIX SUPPORT OF FONT ASSET LOADING")

            case dm.SoundAssetDescriptor:
                asset.handle = cast(dm.Handle) dm.LoadSoundFromMemoryCtx(&engineData.audio, data)

            case dm.RawFileAssetDescriptor:
                data, ok := os.read_entire_file(path)
                if ok {
                    asset.fileData = data
                }
            }
        }
    }

    gameCode.gameLoad(&engineData)

    sdl.ShowWindow(window)

    for shouldClose := false; !shouldClose; {
        free_all(context.temp_allocator)

        // Game code hot reload
        newTime, err2 := os.last_write_time_by_name("Game.dll")
        if newTime > gameCode.lastWriteTime {
            res := ReloadGameCode(&gameCode, "Game.dll")
            // gameCode.gameLoad(&engineData)
            if res {
                gameCode.setStatePointers(&engineData)
                gameCode.gameHotReloaded(engineData.gameState)
            }
        }

        // Assets Hot Reload
        for name, &asset in &engineData.assets.assetsMap {
            switch desc in asset.descriptor {
            case dm.FontAssetDescriptor, dm.SoundAssetDescriptor:
                continue

            case dm.TextureAssetDescriptor:
                path := strings.concatenate({dm.ASSETS_ROOT, name}, context.temp_allocator)
                newTime, err := os.last_write_time_by_name(path)
                if err == os.ERROR_NONE && newTime > asset.lastWriteTime {
                    data, ok := os.read_entire_file(path, context.temp_allocator)
                    if ok {
                        // image, pngErr := png.load_from_bytes(data, allocator = context.temp_allocator)
                        // if pngErr == nil {
                        //     tex := dm.GetTextureCtx(engineData.renderCtx, auto_cast asset.handle)
                        //     dm._ReleaseTexture(tex)
                        //     dm._InitTexture(engineData.renderCtx, tex, image.pixels.buf[:], image.width, image.height, image.channels, desc.filter)

                        //     asset.lastWriteTime = newTime
                        // }
                    }
                }

            case dm.ShaderAssetDescriptor:
                path := strings.concatenate({dm.ASSETS_ROOT, name}, context.temp_allocator)
                newTime, err := os.last_write_time_by_name(path)
                if err == os.ERROR_NONE && newTime > asset.lastWriteTime {
                    data, ok := os.read_entire_file(path, context.temp_allocator)
                    if ok {
                        handle := dm.ShaderHandle(asset.handle)
                        dm.DestroyShader(engineData.renderCtx, handle, freeHandle = false)

                        shader, ok := dm.GetElementPtr(engineData.renderCtx.shaders, handle)
                        source := strings.string_from_ptr(raw_data(data), len(data))
                        dm.InitShaderSource(engineData.renderCtx, shader, source)

                        asset.lastWriteTime = newTime
                        fmt.println("Reloading shader:", name)
                    }
                }
            case dm.RawFileAssetDescriptor: // @TODO: I'm not sure how to handle that, or even if I should?
            }

        }

        // Frame Begin
        dm.TimeUpdate(&engineData)

        // Input
        for key, state in engineData.input.curr {
            engineData.input.prev[key] = state
        }

        for mouseBtn, i in engineData.input.mouseCurr {
            engineData.input.mousePrev[i] = engineData.input.mouseCurr[i]
        }

        engineData.input.runesCount = 0
        engineData.input.scrollX = 0;
        engineData.input.scroll = 0;
        engineData.input.mouseDelta = {}

        for e: sdl.Event; sdl.PollEvent(&e); {
            #partial switch e.type {

            case .QUIT:
                shouldClose = true

            case .KEYDOWN: 
                key := SDLKeyToKey[e.key.keysym.scancode]

                // if key == .Esc {
                //     shouldClose = true
                // }

                engineData.input.curr[key] = .Down

            case .KEYUP:
                key := SDLKeyToKey[e.key.keysym.scancode]
                engineData.input.curr[key] = .Up

            case .MOUSEMOTION:
                engineData.input.mousePos.x = e.motion.x
                engineData.input.mousePos.y = e.motion.y

                engineData.input.mouseDelta.x = e.motion.xrel
                engineData.input.mouseDelta.y = e.motion.yrel

                // fmt.println("mouseDelta: ", engineData.input.mouseDelta)

            case .MOUSEWHEEL:
                engineData.input.scroll  = int(e.wheel.y)
                engineData.input.scrollX = int(e.wheel.x)

            case .MOUSEBUTTONDOWN:
                btnIndex := e.button.button
                btnIndex = clamp(btnIndex, 0, len(SDLMouseToButton) - 1)

                engineData.input.mouseCurr[SDLMouseToButton[btnIndex]] = .Down

            case .MOUSEBUTTONUP:
                btnIndex := e.button.button
                btnIndex = clamp(btnIndex, 0, len(SDLMouseToButton) - 1)

                engineData.input.mouseCurr[SDLMouseToButton[btnIndex]] = .Up

            case .TEXTINPUT:
                // @TODO: I'm not sure here, I should probably scan entire buffer
                r, i := utf8.decode_rune(e.text.text[:])
                engineData.input.runesBuffer[engineData.input.runesCount] = r
                engineData.input.runesCount += 1
            }
        }

        dm.muiProcessInput(engineData.mui, &engineData.input)
        dm.muiBegin(engineData.mui)

        dm.UIBegin(&engineData.uiCtx,
                   int(engineData.renderCtx.frameSize.x),
                   int(engineData.renderCtx.frameSize.y))

        when ODIN_DEBUG {
            if dm.GetKeyStateCtx(&engineData.input, .U) == .JustPressed {
                engineData.debugState = !engineData.debugState
                engineData.pauseGame = engineData.debugState

                if engineData.debugState {
                    dm.muiShowWindow(engineData.mui, "Debug")
                }
            }

            if engineData.debugState && 
               dm.muiBeginWindow(engineData.mui, "Debug", {0, 0, 100, 240}, nil) {

                dm.muiLabel(engineData.mui, "Unscalled Time:", engineData.time.unscalledTime)
                dm.muiLabel(engineData.mui, "GameTime:", engineData.time.gameTime)
                dm.muiLabel(engineData.mui, "GameDuration:", engineData.time.gameDuration)

                dm.muiLabel(engineData.mui, "Frame:", engineData.time.frame)
                dm.muiLabel(engineData.mui, "FPS:", 1 / engineData.time.deltaTime)
                dm.muiLabel(engineData.mui, "Frame Time:", engineData.time.deltaTime * 1000)

                if dm.muiButton(engineData.mui, "Play" if engineData.pauseGame else "Pause") {
                    engineData.pauseGame = !engineData.pauseGame
                }

                if dm.muiButton(engineData.mui, ">") {
                    engineData.moveOneFrame = true
                }

                dm.muiEndWindow(engineData.mui)
            }
        }

        if gameCode.lib != nil {
            if engineData.pauseGame == false || engineData.moveOneFrame {
                gameCode.gameUpdate(engineData.gameState)
            }

            when ODIN_DEBUG {
                if gameCode.gameUpdateDebug != nil {
                    gameCode.gameUpdateDebug(engineData.gameState, engineData.debugState)
                }
            }

            gameCode.gameRender(engineData.gameState)
        }

        dm.UIEnd()
        dm.DrawUI(engineData.renderCtx)

        dm.FlushCommands(engineData.renderCtx)

        dm.DrawPrimitiveBatch(engineData.renderCtx, &engineData.renderCtx.debugBatch)
        dm.DrawPrimitiveBatch(engineData.renderCtx, &engineData.renderCtx.debugBatchScreen)

        dm.muiEnd(engineData.mui)
        dm.muiRender(engineData.mui, engineData.renderCtx)

        dm.EndFrame(engineData.renderCtx)
    }
}