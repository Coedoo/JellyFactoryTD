package dmcore

SoundHandle :: distinct Handle
Sound :: struct {
    handle: SoundHandle,

    _volume: f32,
    _looping: bool,

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
    return LoadSoundFromMemoryCtx(audio, data)
}

LoadSoundFromMemoryCtx :: proc(audio: ^Audio, data: []u8) -> SoundHandle {
    return _LoadSoundFromMemory(audio, data)
}

LoadSoundFromFile :: proc(path: string) -> SoundHandle {
    return LoadSoundFromFileCtx(audio, path)
}

LoadSoundFromFileCtx :: proc(audio: ^Audio, path: string) -> SoundHandle {
    return _LoadSound(audio, path)
}

PlaySound :: proc(handle: SoundHandle) {
    PlaySoundCtx(audio, handle)
}

PlaySoundCtx :: proc(audio: ^Audio, handle: SoundHandle) {
    _PlaySound(audio, handle)
}

StopSound :: proc(handle: SoundHandle) {
    StopSoundCtx(audio, handle)
}
StopSoundCtx :: proc(audio: ^Audio, handle: SoundHandle) {
    _StopSound(audio, handle)
}


SetVolume :: proc(handle: SoundHandle, volume: f32) {
    SetVolumeCtx(audio, handle, volume)
}

SetVolumeCtx :: proc(audio: ^Audio, handle: SoundHandle, volume: f32) {
    sound, ok := GetElementPtr(audio.sounds, handle)
    if ok == false {
        return
    }

    volume := clamp(volume, 0, 1)
    _SetVolume(sound, volume)

    sound._volume = volume
}

SetLooping :: proc(handle: SoundHandle, looping: bool) {
    SetLoopingCtx(audio, handle, looping)
}

SetLoopingCtx :: proc(audio: ^Audio, handle: SoundHandle, looping: bool) {
    sound, ok := GetElementPtr(audio.sounds, handle)
    if ok == false {
        return
    }

    _SetLooping(sound, looping)

    sound._looping = looping
}