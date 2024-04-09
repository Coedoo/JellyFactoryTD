package platform_wasm

import "core:fmt"

foreign import files "files"
foreign files {
    LoadFile :: proc "contextless" (path: string, callback: FileCallback) ---
}

FileCallback :: proc(data: []u8)

@(export)
DoFileCallback :: proc(data: rawptr, len: int, callback: FileCallback) {
    callback(([^]u8)(data)[:len])
}