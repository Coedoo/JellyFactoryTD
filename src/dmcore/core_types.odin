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
CYAN    : color : {0, 1, 1, 1}
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

PointAtRay :: proc(ray: Ray2D, dist: f32) -> v2 {
    return ray.origin + ray.direction * dist
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

SpriteBounds :: proc(sprite: Sprite, position: v2) -> Bounds2D {
    spriteSize: v2
    spriteSize.x = sprite.scale
    spriteSize.y = f32(sprite.textureSize.y) / f32(sprite.textureSize.x) * spriteSize.x

    anchor := sprite.origin
    bounds := CreateBounds(position, spriteSize, anchor)

    return bounds
}

///////////

TimeData :: struct {
    startTime: time.Tick,

    prevTime: time.Tick,
    currTime: time.Tick,
    accumulator: f64,

    deltaTime: f32,
    renderFrame: uint,
    tickFrame: uint,

    gameTickTime: time.Duration,

    gameTime: f64,
    realTime: f64, // time as if game was never paused
}

TimeInit :: proc(timeData: ^TimeData) {
    timeData.startTime = time.tick_now()

    // platform.time.startTimestamp = time.now()
    timeData.currTime = time.tick_now()
    timeData.prevTime = time.tick_now()
}

TimeUpdate :: proc(platform: ^Platform) {
    platform.time.prevTime = platform.time.currTime
    platform.time.currTime = time.tick_now()

    platform.time.deltaTime = f32(time.tick_diff(platform.time.prevTime, platform.time.currTime))
    platform.time.realTime = time.duration_seconds(time.tick_since(platform.time.startTime));

    if platform.pauseGame == false || platform.moveOneFrame {
        // platform.time.gameDuration += delta

        // platform.time.frame += 1
        // platform.moveOneFrame = false
    }

   // platform.time.gameTime = time.duration_seconds(platform.time.gameDuration)
}

///////////////

// Platform :: struct {
//     mui:       ^Mui,
//     input:     Input,
//     time:      TimeData,
//     renderCtx: ^RenderContext,
//     assets:    Assets,
//     audio:     Audio,
//     uiCtx:     UIContext,

//     gameState: rawptr,

//     debugState: bool,
//     pauseGame: bool,
//     moveOneFrame: bool,

//     SetWindowSize: proc(width, height: int),
// }

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
GameUpdateDebug :: proc(gameState: rawptr)
UpdateStatePointerFunc :: proc(platformPtr: ^Platform)
UpdateAndRender :: proc(platform: ^Platform)