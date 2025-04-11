#+build windows
package dmcore

import "core:fmt"
import "core:strings"
import "core:slice"

import ma "vendor:miniaudio"

SoundBackend :: struct {
    maSound: ma.sound,

    // @NOTE:
    // This is needed when loading sound from memory
    // When loading it from file, miniaudio manages
    // the memory itselft, I believe @TODO: check that
    // Maybe the better approach would be to always
    // load file to memory and keeping track of it myself?
    decoder: ma.decoder,
    encodedData: []u8
}

AudioBackend :: struct {
    engine: ma.engine,
}

_InitAudio :: proc(audio: ^Audio) {
    // @TODO: error handling, config
    result := ma.engine_init(nil, &audio.engine)
    if result != .SUCCESS {
        panic("HUH?")
    }

}

_LoadSoundFromMemory :: proc(audio: ^Audio, data: []u8) -> SoundHandle {
    sound := CreateElement(&audio.sounds)
    sound.encodedData = slice.clone(data)

    result := ma.decoder_init_memory(raw_data(sound.encodedData), len(sound.encodedData), nil, &sound.decoder)

    defer if result != .SUCCESS {
        FreeSlot(&audio.sounds, sound.handle)
        delete(sound.encodedData)
    }

    if result != .SUCCESS {
        fmt.eprintln("Failed to init decoder from memory")
        return {}
    }

    result = ma.sound_init_from_data_source(&audio.engine, cast(^ma.data_source) &sound.decoder, {}, nil, &sound.maSound)

    if result != .SUCCESS {
        fmt.eprintln("Failed to init sound from decoder")
        return {}
    }

    sound.volume = 1
    return sound.handle
}

_LoadSoundFromFile :: proc(audio: ^Audio, path: string) -> SoundHandle {
    sound := CreateElement(&audio.sounds)
    path := strings.clone_to_cstring(path, context.temp_allocator)
    result := ma.sound_init_from_file(&audio.engine, path, {}, nil, nil, &sound.maSound)

    if result != .SUCCESS {
        FreeSlot(&audio.sounds, sound.handle)
        fmt.eprintf("Cant't load audio file at: '", path, "'")
        return {}
    }

    sound.volume = 1
    return sound.handle
}

_PlaySound :: proc(audio: ^Audio, handle: SoundHandle) {
    sound, ok := GetElementPtr(audio.sounds, handle)
    if ok == false {
        return
    }

    if(sound.delay != 0) {
        currentTime := ma.engine_get_time_in_milliseconds(&audio.engine)
        ma.sound_set_start_time_in_milliseconds(&sound.maSound, currentTime + u64(sound.delay * 1000))
    }

    ma.sound_set_volume(&sound.maSound, sound.volume)
    ma.sound_set_pan(&sound.maSound, sound.pan)
    ma.sound_set_looping(&sound.maSound, b32(sound.looping))

    ma.sound_seek_to_pcm_frame(&sound.maSound, 0)
    ma.sound_start(&sound.maSound)
}

_SetVolume :: proc(handle: SoundHandle, volume: f32) {
    sound, ok := GetElementPtr(audio.sounds, handle)
    if ok == false {
        return
    }

    ma.sound_set_volume(&sound.maSound, sound.volume)
}

_StopSound :: proc(audio: ^Audio, handle: SoundHandle) {
    sound, ok := GetElementPtr(audio.sounds, handle)
    if ok == false {
        return
    }

    ma.sound_stop(&sound.maSound)
}
