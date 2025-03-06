package dmcore

import "core:math"
import "core:math/linalg/glsl"

import "core:math/rand"


DirectionFromRotation :: proc(rotation: f32) -> v2 {
    return {
        math.cos(math.to_radians(rotation)),
        math.sin(math.to_radians(rotation)),
    }
}


ToV2 :: proc {
    ToV2FromIV2,
    ToV2FromV3,
}

ToV2FromIV2 :: proc(v: iv2) -> v2 {
    return {f32(v.x), f32(v.y)}
}

ToV2FromV3 :: proc(v: v3) -> v2 {
    return {v.x, v.y}
}

ToIv2 :: proc {
    ToIv2FromV2,
}

ToIv2FromV2 :: proc(v: v2) -> iv2 {
    return {i32(v.x), i32(v.y)}
}

ToV3 :: proc {
    ToV3FromV2
}

ToV3FromV2 :: proc(v: v2) -> v3 {
    return {v.x, v.y, 0}
}

IsPointInsideRect :: proc(point: v2, rect: Rect) -> bool {
    return point.x > rect.x &&
           point.x < rect.x + rect.width &&
           point.y > rect.y &&
           point.y < rect.y + rect.height
}

//////////
// Collisions
/////////

CheckCollisionBounds :: proc(a, b: Bounds2D) -> bool {
    return a.left  <= b.right &&
           a.right >= b.left  &&
           a.bot   <= b.top   &&
           a.top   >= b.bot
}

CheckCollisionCircles :: proc(aPos: v2, aRad: f32, bPos: v2, bRad: f32) -> bool {
    delta := aPos - bPos
    sum := aRad + bRad 
    return delta.x * delta.x + delta.y * delta.y <= sum * sum
}

CheckCollisionBoundsCircle :: proc(a: Bounds2D, bPos: v2, bRad: f32) -> bool {
    collision, point := GetCollisionBoundsCircle(a, bPos, bRad)
    return collision
}

GetCollisionBoundsCircle :: proc(a: Bounds2D, bPos: v2, bRad: f32) -> (bool, v2) {
    x := clamp(bPos.x, a.left, a.right)
    y := clamp(bPos.y, a.bot, a.top)

    dist := (x - bPos.x) * (x - bPos.x) +
            (y - bPos.y) * (y - bPos.y)

    return dist < bRad * bRad, v2{x, y}
}

RaycastAABB2D :: proc(ray: Ray2D, aabb: Bounds2D, distance := max(f32)) -> (bool, f32) {
    // https://tavianator.com/2011/ray_box.html

    tx1 := (aabb.left - ray.origin.x) * ray.invDir.x
    tx2 := (aabb.right - ray.origin.x) * ray.invDir.x

    tMin := min(tx1, tx2)
    tMax := max(tx1, tx2)

    ty1 := (aabb.bot - ray.origin.y) * ray.invDir.y
    ty2 := (aabb.top - ray.origin.y) * ray.invDir.y

    tMin = max(tMin, min(ty1, ty2))
    tMax = min(tMax, max(ty1, ty2))

    return tMax >= tMin && tMax > 0 && tMin > 0 && tMin < distance, (tMin < 0 ? tMax : tMin)
}

//////

CosRange :: proc(a, b:f32, rad: f32) -> f32 {
    s := math.cos(rad) * 0.5 + 0.5
    return a + (b - a) * s
}

MoveTowards :: proc(current, target: v2, maxDist: f32) -> (v2, f32)
{
    delta := target - current
    magnitude := glsl.length(delta)
    if magnitude <= maxDist || magnitude == 0 {
        return target, maxDist - magnitude
    }

    point := current + delta / magnitude * maxDist

    return point, 0
}

/////

RandomDirection :: proc() -> v2 {
    angle := rand.float32() * math.PI * 2
    return {
        math.cos(angle),
        math.sin(angle)
    }
}