#+build js
package dmcore

import "core:fmt"
import "core:strings"

foreign import audio "audio"
foreign audio {
    Load :: proc "c" (dataPtr: rawptr, dataLen: int) ---
    Play :: proc "c" (dataPtr: rawptr, volume: f32, pan: f32, delay: f32) ---
    Stop :: proc "c" (dataPtr: rawptr) ---
}


SoundBackend :: struct {
    ptr: rawptr
}

AudioBackend :: struct {
}

_InitAudio :: proc(audio: ^Audio) {

}

_LoadSoundFromFile :: proc(audio: ^Audio, path: string) -> SoundHandle {
    panic("Unsupported on wasm target")
}

_LoadSoundFromMemory :: proc(audio: ^Audio, data: []u8) -> SoundHandle {
    Load(raw_data(data), len(data))
    sound := CreateElement(&audio.sounds)

    sound.volume = 0.5
    sound.ptr = raw_data(data)

    return sound.handle
}

_PlaySound :: proc(audio: ^Audio, handle: SoundHandle) {
    sound, ok := GetElementPtr(audio.sounds, handle)
    Play(sound.ptr, sound.volume, sound.pan, sound.delay)
}

_StopSound :: proc(audio: ^Audio, handle: SoundHandle) {
    sound, ok := GetElementPtr(audio.sounds, handle)
    Stop(sound.ptr)
}