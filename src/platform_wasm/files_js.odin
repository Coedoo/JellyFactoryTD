package platform_wasm

import "core:fmt"

foreign import files "files"
foreign files {
    LoadFile :: proc "contextless" (path: string, key: string, callback: FileCallback) ---
}

FileCallback :: proc(data: []u8, key: string)

@(export)
DoFileCallback :: proc(data: rawptr, len: int, key: [^]byte, keyLen: int, callback: FileCallback) {
    callback(([^]u8)(data)[:len], string(key[:keyLen]))
}