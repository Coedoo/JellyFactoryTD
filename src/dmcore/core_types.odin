package dmcore

import math "core:math/linalg/glsl"

import "core:time"

// Math types
v2  :: math.vec2
iv2 :: math.ivec2

v3 :: math.vec3
iv3 :: math.ivec3

v4 :: math.vec4

mat4 :: math.mat4

color :: math.vec4

Range :: struct {
    min, max: i32
}

WHITE   : color : {1, 1, 1, 1}
BLACK   : color : {0, 0, 0, 1}
GRAY    : color : {0.3, 0.3, 0.3, 1}
RED     : color : {1, 0, 0, 1}
GREEN   : color : {0, 1, 0, 1}
BLUE    : color : {0, 0, 1, 1}
SKYBLUE : color : {0.4, 0.75, 1, 1}
LIME    : color : {0, 0.62, 0.18, 1}
DARKGREEN : color : {0, 0.46, 0.17, 1}
MAGENTA : color : {1, 0, 1, 1}


Rect :: struct {
    x, y: f32,
    width, height: f32,
}

RectInt :: struct {
    x, y: i32,
    width, height: i32,
}

Bounds2D :: struct {
    left, right: f32,
    bot, top: f32,
}

Ray :: struct {
    origin, direction: v3
}

Ray2D :: struct {
    origin, direction: v2,
    invDir: v2,
}

CreateBounds :: proc(pos: v2, size: v2, anchor: v2 = {0.5, 0.5}) -> Bounds2D {
    anchor := math.saturate(anchor)

    return {
        left  = pos.x - size.x * anchor.x,
        right = pos.x + size.x * (1 - anchor.x),
        bot   = pos.y - size.y * anchor.y,
        top   = pos.y + size.y * (1 - anchor.y),
    }
}

BoundsCenter :: proc(bound: Bounds2D) -> v2 {
    return {
        (bound.left + bound.right) / 2,
        (bound.bot  + bound.top)   / 2,
    }
}

CreateRay2D :: proc(pos: v2, dir: v2) -> Ray2D {
    d := math.normalize(dir)
    return {
        pos, d, 1 / d,
    }
}

Ray2DFromTwoPoints :: proc(a, b: v2) -> Ray2D {
    delta := math.normalize(b - a)
    return {
        a,
        delta,
        1 / delta,
    }
}

IsInBounds :: proc(bounds: Bounds2D, point: v2) -> bool {
    return point.x > bounds.left && point.x < bounds.right &&
           point.y > bounds.bot && point.y < bounds.top
}

///////////

TimeData :: struct {
    startTimestamp: time.Time,

    lastTimestamp: time.Time,
    currentTimestamp: time.Time,

    gameDuration: time.Duration,

    deltaTime: f64,
  
    frame: uint,

    gameTime: f64,
    unscalledTime: f64, // time as if game was never paused
}

TimeInit :: proc(platform: ^Platform) {
    platform.time.startTimestamp = time.now()
    platform.time.currentTimestamp = time.now()
}

TimeUpdate :: proc(platform: ^Platform) {
    platform.time.lastTimestamp = platform.time.currentTimestamp
    platform.time.currentTimestamp = time.now()

    delta := time.diff(platform.time.lastTimestamp, platform.time.currentTimestamp)
    platform.time.deltaTime = time.duration_seconds(delta)

    gameDelta := time.diff(platform.time.startTimestamp, platform.time.currentTimestamp)
    platform.time.unscalledTime = time.duration_seconds(gameDelta)

    if platform.pauseGame == false || platform.moveOneFrame {
        platform.time.gameDuration += delta

        platform.time.frame += 1
        platform.moveOneFrame = false
    }

    platform.time.gameTime = time.duration_seconds(platform.time.gameDuration)
}

///////////////

Platform :: struct {
    mui:       ^Mui,
    input:     Input,
    time:      TimeData,
    renderCtx: ^RenderContext,
    assets:    Assets,
    audio:     Audio,
    uiCtx:     UIContext,

    gameState: rawptr,

    debugState: bool,
    pauseGame: bool,
    moveOneFrame: bool,

    SetWindowSize: proc(width, height: int),
}

AllocateGameData :: proc(platform: ^Platform, $type: typeid) -> ^type {
    platform.gameState = new(type)

    return cast(^type) platform.gameState
}

///////

PreGameLoad :: proc(assets: ^Assets)
GameHotReloaded :: proc(gameState: rawptr)
GameLoad    :: proc(platform: ^Platform)
GameUpdate  :: proc(gameState: rawptr)
GameRender  :: proc(gameState: rawptr)
GameReload  :: proc(gameState: rawptr)
GameUpdateDebug :: proc(gameState: rawptr, debug: bool)
UpdateStatePointerFunc :: proc(platformPtr: ^Platform)
