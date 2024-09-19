package dmcore

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:math/ease"

EaseFun :: ease.Ease

ValueOverLifetime :: struct($vT: typeid) {
    min, max: vT,
    easeFun: EaseFun,
}

FloatOverLifetime :: ValueOverLifetime(f32)
ColorOverLifetime :: ValueOverLifetime(color)

FloatLifetimeProp :: union {
    f32,
    FloatOverLifetime,
}

ColorLifetimeProp :: union {
    color,
    ColorOverLifetime,
}

EvaluateLifetime :: proc(value: ValueOverLifetime($vT), time: f32) -> vT {
    t := ease.ease(value.easeFun, time)
    return math.lerp(value.min, value.max, time)
}

RandomValue :: struct($vT: typeid) {
    min, max: vT,
}

RandomFloat :: RandomValue(f32)
RandomColor :: RandomValue(color)

FloatStartProp :: union {
    f32,
    RandomFloat,
}

ColorStartProp :: union {
    color,
    RandomColor,
}

EvaluateRandomProp :: proc(value: RandomValue($vT)) -> vT {
    t := rand.float32_range(0, 1)
    return math.lerp(value.min, value.max, t)
}

ParticleSystem :: struct {
    maxParticles: int,
    emitRate: f32,

    burstCount: int,
    burstInterval: f32,
    burstTimer: f32,

    lifetime: FloatStartProp,

    startColor: ColorStartProp,
    color: ColorLifetimeProp,

    startSize: FloatStartProp,
    size: FloatLifetimeProp,

    startSpeed: FloatStartProp,
    speed: FloatOverLifetime,

    gravity: v2,

    position: v2,
    texture: TexHandle,

    toAdd: f32,
    particles: [dynamic]Particle,
}

Particle :: struct {
    lifetime: f32,
    maxLifetime: f32,

    startColor: color,
    color: color,

    position: v2,
    velocity: v2,

    rotation: f32,
    rotationSpeed: f32,

    startSize: f32,
    size: f32,
}

DefaultParticleSystem := ParticleSystem{
    maxParticles = 1024,
    lifetime = 1.5,

    startColor = WHITE,
    color = WHITE,

    startSize = 1,
    size = 1,

    emitRate = 20,
}

RandAtUnitCircle :: proc() -> v2 {
    angle := rand.float32() * math.PI * 2
    x := math.cos(angle)
    y := math.sin(angle)

    return {x, y}
}

InitParticleSystem :: proc(system: ^ParticleSystem) {
    system.particles = make([dynamic]Particle, 0, system.maxParticles)
    // AddParticles(system, system.burstCount)
}

SpawnParticles :: proc(system: ^ParticleSystem, count: int, 
    atPosition: Maybe(v2) = nil, 
    tint := color{1, 1, 1, 1})
{
    maxToAdd := system.maxParticles - len(system.particles)
    count := min(count, maxToAdd)

    for i in 0..<count {
        particle := Particle {
            velocity = RandAtUnitCircle(),
            position = atPosition.? or_else system.position,
            rotationSpeed = (rand.float32() * 2 - 1),
        }

        switch s in system.startSpeed {
            case f32: 
                particle.velocity *= s
            case RandomFloat:
                particle.velocity *= EvaluateRandomProp(s)
        }

        switch s in system.lifetime {
            case f32: 
                particle.lifetime = s
                particle.maxLifetime = s
            case RandomFloat:
                v :=  EvaluateRandomProp(s)
                particle.maxLifetime = v 
                particle.lifetime = v
        }

        switch s in system.startColor {
            case color: 
                particle.startColor = s * tint
            case RandomColor:
                v :=  EvaluateRandomProp(s)
                particle.startColor = v * tint
        }

        switch s in system.startSize {
            case f32: 
                particle.startSize = s
            case RandomFloat:
                v :=  EvaluateRandomProp(s)
                particle.startSize = v 
        }

        append(&system.particles, particle)
    }
}

UpdateParticleSystem :: proc(system: ^ParticleSystem, deltaTime: f32) {
    // Burst
    if system.burstCount != 0 {
        if system.burstTimer <= 0 {
            SpawnParticles(system, system.burstCount)
            system.burstTimer = system.burstInterval
        }
        system.burstTimer -= deltaTime
    }

    // Emition
    system.toAdd += system.emitRate * deltaTime
    toAdd := int(system.toAdd)
    system.toAdd -= f32(toAdd)

    SpawnParticles(system, toAdd)

    // State update
    #reverse for &particle, i in system.particles {
        particle.lifetime -= deltaTime
        if particle.lifetime <= 0 {
            unordered_remove(&system.particles, i)
            continue
        }

        lifePercent := particle.lifetime / particle.maxLifetime
        particle.velocity += system.gravity * deltaTime
        particle.position += particle.velocity * deltaTime
        particle.rotation += particle.rotationSpeed * deltaTime

        switch size in system.size {
        case f32:
            particle.size = particle.startSize * size
        case ValueOverLifetime(f32):
            particle.size = particle.startSize * EvaluateLifetime(size, 1 - lifePercent)
        }
        
        switch color in system.color {
        case color:
            particle.color = particle.startColor * color
        case ValueOverLifetime(color):
            particle.color = particle.startColor * EvaluateLifetime(color, 1 - lifePercent)
        }
    }
}

DrawParticleSystem :: proc(ctx: ^RenderContext, system: ^ParticleSystem) {
    #reverse for particle in system.particles {
        DrawWorldRect(system.texture, 
                      particle.position, 
                      particle.size, 
                      rotation = particle.rotation,
                      color = particle.color
                    )
    }
}

UpdateAndDrawParticleSystem :: proc(system: ^ParticleSystem) {
    UpdateParticleSystem(system, f32(time.deltaTime))
    DrawParticleSystem(renderCtx, system)
}