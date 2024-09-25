#+build js
package dmcore

import "core:fmt"
import "core:strings"

foreign import audio "audio"
foreign audio {
    Load :: proc "c" (dataPtr: rawptr, dataLen: int) ---
    Play :: proc "c" (dataPtr: rawptr) ---
    jsSetVolume :: proc "c" (dataPtr: rawptr, volume: f32) ---
    jsSetLooping :: proc "c" (dataPtr: rawptr, volume: bool) ---
}


SoundBackend :: struct {
    ptr: rawptr
}

AudioBackend :: struct {
}

_InitAudio :: proc(audio: ^Audio) {

}

_LoadSound :: proc(audio: ^Audio, path: string) -> SoundHandle {
    panic("Unsupported on wasm target")
}

_LoadSoundFromMemory :: proc(audio: ^Audio, data: []u8) -> SoundHandle {
    Load(raw_data(data), len(data))
    sound := CreateElement(&audio.sounds)

    sound._volume = 1
    sound.ptr = raw_data(data)

    return sound.handle
}

_PlaySound :: proc(audio: ^Audio, handle: SoundHandle) {
    sound, ok := GetElementPtr(audio.sounds, handle)
    Play(sound.ptr)
}

_SetVolume :: proc(sound: ^Sound, volume: f32) {
    sound._volume = volume
    jsSetVolume(sound.ptr, volume)
}

_SetLooping :: proc(sound: ^Sound, looping: bool) {
    sound._looping = looping
    jsSetLooping(sound.ptr, looping)
}


_StopSound :: proc(audio: ^Audio, handle: SoundHandle) {
}