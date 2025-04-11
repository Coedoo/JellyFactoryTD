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

    if engineData.renderCtx.screenRenderTarget != nil {
        engineData.renderCtx.screenRenderTarget->Release()
    }

    engineData.renderCtx.swapchain->ResizeBuffers(0, cast(u32) width, cast(u32) height, .UNKNOWN, nil)

    screenBuffer: ^d3d11.ITexture2D
    engineData.renderCtx.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&screenBuffer))

    engineData.renderCtx.device->CreateRenderTargetView(screenBuffer, nil, &engineData.renderCtx.screenRenderTarget)
    screenBuffer->Release()

    dm.ResizeFramebuffer(engineData.renderCtx, engineData.renderCtx.ppFramebufferSrc)
    dm.ResizeFramebuffer(engineData.renderCtx, engineData.renderCtx.ppFramebufferDest)
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
    dm.InitPlatform(&engineData)
    // dm.InitRenderContext(engineData.renderCtx)

    // // Other Init
    // dm.muiInit(&engineData.tickMui, engineData.renderCtx)
    // dm.muiInit(&engineData.frameMui, engineData.renderCtx)
    // dm.InitUI(&engineData.uiCtx, engineData.renderCtx)

    // dm.InitAudio(&engineData.audio)

    // dm.TimeInit(&engineData)

    context.random_generator = rand.default_random_generator()

    dm.UpdateStatePointers(&engineData)

    // gameCode: dm.GameCode
    if LoadGameCode(&engineData.gameCode, "Game.dll") == false {
        return
    }

    engineData.gameCode.setStatePointers(&engineData)

    // Assets loading!
    if engineData.gameCode.preGameLoad != nil {
        engineData.gameCode.preGameLoad(&engineData.assets)

        for name, &asset in engineData.assets.assetsMap {
            if asset.descriptor == nil {
                fmt.eprintln("Incorrect asset descriptor for asset:", name)
                continue
            }

            path := strings.concatenate({dm.ASSETS_ROOT, asset.fileName}, context.temp_allocator)
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
                asset.handle = cast(dm.Handle) dm.CompileShaderSource(engineData.renderCtx, name, str)

            case dm.FontAssetDescriptor:
                if desc.fontType == .SDF {
                    asset.handle = dm.LoadFontSDF(engineData.renderCtx, data, desc.fontSize)
                }
                else {
                    panic("FIX ME")
                }

            case dm.SoundAssetDescriptor:
                asset.handle = cast(dm.Handle) dm.LoadSoundFromMemory(data)

            case dm.RawFileAssetDescriptor:
                fileData, fileOk := os.read_entire_file(path)
                if fileOk {
                    asset.fileData = fileData
                }
            }
        }
    }

    engineData.gameCode.gameLoad(&engineData)

    sdl.ShowWindow(window)

    // @HACK
    for &state in engineData.frameInput.key {
        state += {.Up}
    }
    for &state in engineData.tickInput.key {
        state += {.Up}
    }

    for shouldClose := false; !shouldClose; {
        frameStart := sdl.GetPerformanceCounter()
        free_all(context.temp_allocator)

        // Game code hot reload
        newTime, err2 := os.last_write_time_by_name("Game.dll")
        if newTime > engineData.gameCode.lastWriteTime {
            res := ReloadGameCode(&engineData.gameCode, "Game.dll")
            // engineData.gameCode.gameLoad(&engineData)
            if res {
                engineData.gameCode.setStatePointers(&engineData)
                if engineData.gameCode.gameHotReloaded != nil {
                    engineData.gameCode.gameHotReloaded(engineData.gameState)
                }
            }
        }

        // Assets Hot Reload
        dm.CheckAndHotReloadAssets(&engineData.assets)

        for e: sdl.Event; sdl.PollEvent(&e); {
            #partial switch e.type {

            case .QUIT:
                shouldClose = true

            case .KEYDOWN: 
                key := SDLKeyToKey[e.key.keysym.scancode]

                when ODIN_DEBUG {
                    if key == .Esc {
                        shouldClose = true
                    }
                }

                if .Up in engineData.tickInput.key[key] {
                    engineData.tickInput.key[key] -= { .Up }
                    engineData.tickInput.key[key] += { .Down, .JustPressed }
                }

                if .Up in engineData.frameInput.key[key] {
                    engineData.frameInput.key[key] -= { .Up }
                    engineData.frameInput.key[key] += { .Down, .JustPressed }
                }


            case .KEYUP:
                key := SDLKeyToKey[e.key.keysym.scancode]

                if .Down in engineData.tickInput.key[key] {
                    engineData.tickInput.key[key] -= { .Down }
                    engineData.tickInput.key[key] += { .Up, .JustReleased }
                }

                if .Down in engineData.frameInput.key[key] {
                    engineData.frameInput.key[key] -= { .Down }
                    engineData.frameInput.key[key] += { .Up, .JustReleased }
                }


            case .MOUSEMOTION:
                engineData.tickInput.mousePos.x = e.motion.x
                engineData.tickInput.mousePos.y = e.motion.y

                engineData.tickInput.mouseDelta.x += e.motion.xrel
                engineData.tickInput.mouseDelta.y += e.motion.yrel

                engineData.frameInput.mousePos.x = e.motion.x
                engineData.frameInput.mousePos.y = e.motion.y

                engineData.frameInput.mouseDelta.x += e.motion.xrel
                engineData.frameInput.mouseDelta.y += e.motion.yrel

                // fmt.println("mouseDelta: ", engineData.frameInput.mouseDelta)

            case .MOUSEWHEEL:
                engineData.tickInput.scroll  += int(e.wheel.y)
                engineData.tickInput.scrollX += int(e.wheel.x)

                engineData.frameInput.scroll  += int(e.wheel.y)
                engineData.frameInput.scrollX += int(e.wheel.x)

            case .MOUSEBUTTONDOWN:
                btnIndex := e.button.button
                btnIndex = clamp(btnIndex, 0, len(SDLMouseToButton) - 1)

                // engineData.frameInput.mouseCurr[SDLMouseToButton[btnIndex]] = .Down
                btn := SDLMouseToButton[btnIndex]

                engineData.tickInput.mouseKey[btn] -= { .Up }
                engineData.tickInput.mouseKey[btn] += { .Down, .JustPressed }

                engineData.frameInput.mouseKey[btn] -= { .Up }
                engineData.frameInput.mouseKey[btn] += { .Down, .JustPressed }

            case .MOUSEBUTTONUP:
                btnIndex := e.button.button
                btnIndex = clamp(btnIndex, 0, len(SDLMouseToButton) - 1)

                // engineData.frameInput.mouseCurr[SDLMouseToButton[btnIndex]] = .Up
                btn := SDLMouseToButton[btnIndex]

                engineData.tickInput.mouseKey[btn] -= { .Down }
                engineData.tickInput.mouseKey[btn] += { .Up, .JustReleased }

                engineData.frameInput.mouseKey[btn] -= { .Down }
                engineData.frameInput.mouseKey[btn] += { .Up, .JustReleased }

            case .TEXTINPUT:
                // @TODO: I'm not sure here, I should probably scan entire buffer
                // r, i := utf8.decode_rune(e.text.text[:])
                // engineData.frameInput.runesBuffer[engineData.frameInput.runesCount] = r
                // engineData.frameInput.runesCount += 1
            }
        }

        engineData.gameCode.updateAndRender(&engineData)
    }
}