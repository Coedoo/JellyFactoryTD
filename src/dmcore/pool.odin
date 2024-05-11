package dmcore

import "core:mem"
import "core:slice"

import "core:intrinsics"

Handle :: struct {
    index: i32,
    gen: i32,
}

PoolSlot :: struct {
    inUse: bool,
    gen: i32,
}

ResourcePool :: struct($T:typeid, $H:typeid) {
    slots: []PoolSlot,
    elements: []T,
}

InitResourcePool :: proc(pool: ^ResourcePool($T, $H), len: int, allocator := context.allocator) -> bool {
    assert(pool != nil)

    pool.slots    = make([]PoolSlot, len, allocator)
    pool.elements = make([]T, len, allocator)

    return pool.slots != nil && pool.elements != nil
}

CreateHandle :: proc(pool: ResourcePool($T, $H)) -> H {
    for &s, i in pool.slots {
        // slot at index 0 is reserved as "invalid resorce" 
        // so never allocate at it

        if s.inUse == false && i != 0 {
            s.inUse = true
            s.gen += 1

            return H {
                index = i32(i),
                gen = s.gen,
            }
        }
    }

    return {}
}

CreateElement :: proc(pool: ResourcePool($T, $H)) -> ^T {
    handle := CreateHandle(pool)
    assert(handle.index != 0)

    elem := &pool.elements[handle.index]
    elem.handle = handle

    return elem
}

AppendElement :: proc(pool: ^ResourcePool($T, $H), element: T) -> H {
    handle := CreateHandle(pool^)
    if handle != {} {
        pool.elements[handle.index] = element
        pool.elements[handle.index].handle = handle
    }

    return handle
}

IsHandleValid :: proc(pool: ResourcePool($T, $H), handle: H) -> bool {
    assert(int(handle.index) < len(pool.slots))

    slot := pool.slots[handle.index]
    return slot.inUse && slot.gen == handle.gen
}

GetElementPtr :: proc(pool: ResourcePool($T, $H), handle: H) -> (element: ^T, ok: bool) {
    if IsHandleValid(pool, handle) == false {
        return &pool.elements[handle.index], false
    }

    return &pool.elements[handle.index], true
}

GetElement :: proc(pool: ResourcePool($T, $H), handle: H) -> T {
    if IsHandleValid(pool, handle) == false {
        return pool.elements[0]
    }

    return pool.elements[handle.index]
}

FreeSlot :: proc {
    FreeSlotAtIndex,
    FreeSlotAtHandle,
}

FreeSlotAtIndex :: proc(pool: ResourcePool($T, $H), index: i32) {
    assert(index < cast(i32) len(pool.slots))

    pool.slots[index].inUse = false
    mem.zero_item(&pool.elements[index])
}

FreeSlotAtHandle :: proc(pool: ResourcePool($T, $H), handle: H) {
    FreeSlotAtIndex(pool, handle.index)
}

ClearPool :: proc(pool: ResourcePool($T, $H)) {
    slice.zero(pool.slots)
    slice.zero(pool.elements)
}