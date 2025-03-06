package dmcore

SoundHandle :: distinct Handle
Sound :: struct {
    handle: SoundHandle,

    volume: f32,
    looping: bool,
    pan: f32,
    delay: f32,

    using backend: SoundBackend,
}

Audio :: struct {
    sounds: ResourcePool(Sound, SoundHandle),
    using backend: AudioBackend
}

InitAudio :: proc(audio: ^Audio) {
    InitResourcePool(&audio.sounds, 64)
    _InitAudio(audio)
}

LoadSound :: proc {
    LoadSoundFromMemory,
    LoadSoundFromFile,
}

LoadSoundFromMemory :: proc(data: []u8) -> SoundHandle {
    return _LoadSoundFromMemory(audio, data)
}

LoadSoundFromFile :: proc(path: string) -> SoundHandle {
    return _LoadSoundFromFile(audio, path)
}

PlaySound :: proc(handle: SoundHandle) {
    _PlaySound(audio, handle)
}

StopSound :: proc(handle: SoundHandle) {
    _StopSound(audio, handle)
}

SetVolume :: proc(handle: SoundHandle, volume: f32) {
    sound, ok := GetElementPtr(audio.sounds, handle)
    if ok == false {
        return
    }

    sound.volume = clamp(volume, 0, 1)
}

SetLooping :: proc(audio: ^Audio, handle: SoundHandle, looping: bool) {
    sound, ok := GetElementPtr(audio.sounds, handle)
    if ok == false {
        return
    }

    sound.looping = looping
}

SetPan :: proc(handle: SoundHandle, value: f32) {
    sound, ok := GetElementPtr(audio.sounds, handle)
    if ok == false {
        return
    }

    sound.pan = value
}

SetDelay :: proc(handle: SoundHandle, value: f32) {
    sound, ok := GetElementPtr(audio.sounds, handle)
    if ok == false {
        return
    }

    sound.delay = value
}