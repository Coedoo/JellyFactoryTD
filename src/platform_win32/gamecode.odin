package main

import "core:dynlib"
import "core:os"
import "core:fmt"

import dm "../dmcore"

LoadProc :: proc(lib: dynlib.Library, name: string, $type: typeid) -> type {
    ptr, ok := dynlib.symbol_address(lib, name)
    if ok == false {
        fmt.println("Can't find proc with name: ", name)
        return nil
    }

    return cast(type) ptr
}

LoadGameCode :: proc(gameCode: ^dm.GameCode, libName: string) -> bool {
    @static session: int
    tempLibName :: "Temp%v.dll"

    fmt.println("Loading Game Code...")

    data, r := os.read_entire_file(libName, context.temp_allocator)
    if r == false {
        fmt.println("Cannot Open Game.dll")
        return false
    }

    dllName := fmt.tprintf(tempLibName, session)
    r = os.write_entire_file(dllName, data)

    if r == false {
        fmt.println("Cannot Write to Temp.dll")
        return false
    }

    if gameCode.lib != nil {
        UnloadGameCode(gameCode)
    }

    fmt.println(dllName)
    lib, ok := dynlib.load_library(dllName)
    if ok == false {
        fmt.println("Cannot open game code!")
        return false
    }

    session += 1

    writeTime, err := os.last_write_time_by_name(libName)

    gameCode.lib = lib
    gameCode.lastWriteTime = writeTime;

    gameCode.preGameLoad = LoadProc(lib, "PreGameLoad", dm.PreGameLoad)
    gameCode.gameHotReloaded = LoadProc(lib, "GameHotReloaded", dm.GameHotReloaded)
    gameCode.gameLoad    = LoadProc(lib, "GameLoad",    dm.GameLoad)
    gameCode.gameUpdate  = LoadProc(lib, "GameUpdate",  dm.GameUpdate)
    gameCode.gameRender  = LoadProc(lib, "GameRender",  dm.GameRender)
    gameCode.gameUpdateDebug = LoadProc(lib, "GameUpdateDebug", dm.GameUpdateDebug)
    gameCode.setStatePointers = LoadProc(lib, "UpdateStatePointers", dm.UpdateStatePointerFunc)
    gameCode.updateAndRender = LoadProc(lib, "CoreUpdateAndRender", proc(platform: ^dm.Platform))

    return true
}

UnloadGameCode :: proc(gameCode: ^dm.GameCode) {
    fmt.println("Unloading Game Code...")
    didUnload := dynlib.unload_library(gameCode.lib)

    if didUnload == false {
        fmt.println("FUUUUUUUUUUUUUUCK.....")
    }

    gameCode^ = {} 
}

ReloadGameCode :: proc(gameCode: ^dm.GameCode, libName: string) -> bool {
    result := LoadGameCode(gameCode, libName)

    // assert(result)

    return result
}
