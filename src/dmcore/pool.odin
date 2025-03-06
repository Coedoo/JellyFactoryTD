package dmcore

import "core:mem"
import "core:slice"
import "core:fmt"

import "base:intrinsics"

import "base:runtime"

Handle :: struct {
    slotIndex: i32,
    gen: i32,
}

PoolSlot :: struct {
    elemIndex: i32,
    gen: i32,
}

ResourcePool :: struct($T:typeid, $H:typeid) {
    slots:    [dynamic]PoolSlot,
    elements: [dynamic]T,
}

InitResourcePool :: proc(pool: ^ResourcePool($T, $H), len: int, allocator := context.allocator) -> bool {
    assert(pool != nil)

    pool.slots    = make([dynamic]PoolSlot, len, len, allocator)
    pool.elements = make([dynamic]T,        0,   len, allocator)

    // Append first "error" element
    append(&pool.elements, T{})

    return pool.slots != nil && pool.elements != nil
}

CreateHandle :: proc(pool: ^ResourcePool($T, $H)) -> H {
    for &s, i in pool.slots {
        // slot at index 0 is reserved as "invalid resorce" 
        // so never allocate at it

        if s.elemIndex == 0 && i != 0 {
            append(&pool.elements, T{})

            s.elemIndex = i32(len(pool.elements) - 1)
            s.gen += 1

            return H {
                slotIndex = i32(i),
                gen = s.gen,
            }
        }
    }

    return {}
}

CreateElement :: proc(pool: ^ResourcePool($T, $H)) -> ^T {
    handle := CreateHandle(pool)
    assert(handle.slotIndex != 0)

    slot := pool.slots[handle.slotIndex]
    elem := &pool.elements[slot.elemIndex]
    elem.handle = handle

    return elem
}

AppendElement :: proc(pool: ^ResourcePool($T, $H), element: T) -> H {
    handle := CreateHandle(pool)
    if handle != {} {
        slot := pool.slots[handle.slotIndex]

        pool.elements[slot.elemIndex] = element
        pool.elements[slot.elemIndex].handle = handle
    }

    return handle
}

IsHandleValid :: proc(pool: ResourcePool($T, $H), handle: H) -> bool {
    assert(int(handle.slotIndex) < len(pool.slots))

    slot := pool.slots[handle.slotIndex]
    return slot.elemIndex != 0 && slot.gen == handle.gen
}

GetElementPtr :: proc(pool: ResourcePool($T, $H), handle: H) -> (element: ^T, ok: bool) {
    if IsHandleValid(pool, handle) == false {
        return nil, false
    }

    slot := pool.slots[handle.slotIndex]
    return &pool.elements[slot.elemIndex], true
}

GetElement :: proc(pool: ResourcePool($T, $H), handle: H) -> T {
    if IsHandleValid(pool, handle) == false {
        return pool.elements[0]
    }

    slot := pool.slots[handle.slotIndex]
    return pool.elements[slot.elemIndex]
}

FreeSlot :: proc {
    FreeSlotAtIndex,
    FreeSlotAtHandle,
}

FreeSlotAtIndex :: proc(pool: ^ResourcePool($T, $H), index: i32) {
    assert(index < cast(i32) len(pool.slots))

    lastHandle := pool.elements[len(pool.elements) - 1].handle

    lastElementSlot := &pool.slots[lastHandle.slotIndex]
    elemSlot := &pool.slots[index]

    if lastElementSlot != elemSlot {
        pool.elements[elemSlot.elemIndex] = pool.elements[lastElementSlot.elemIndex]

        lastElementSlot.elemIndex = elemSlot.elemIndex
    }

    elemSlot.elemIndex = 0

    (^runtime.Raw_Dynamic_Array)(&pool.elements).len -= 1
}

FreeSlotAtHandle :: proc(pool: ^ResourcePool($T, $H), handle: H) {
    FreeSlotAtIndex(pool, handle.slotIndex)
}

ClearPool :: proc(pool: ^ResourcePool($T, $H)) {
    // resize(&pool.slots, 0)
    for &s, i in pool.slots {
        s = {}
    }
    clear(&pool.elements)
}

PoolIterator :: struct($T: typeid, $H: typeid) {
    idx: int,
    dir: int,

    pool: ^ResourcePool(T, H)
}

MakePoolIter :: proc(pool: ^ResourcePool($T, $H)) -> PoolIterator(T, H) {
    return {
        idx = 1,
        dir = 1,

        pool = pool
    }
}

MakePoolIterReverse :: proc(pool: ^ResourcePool($T, $H)) -> PoolIterator(T, H) {
    return {
        idx = len(pool.elements) - 1,
        dir = -1,

        pool = pool
    }
}

PoolIterate :: proc(it: ^PoolIterator($T, $H)) -> (^T, bool) {
    if it.idx <= 0 || it.idx >= len(it.pool.elements) {
        return nil, false
    }

    elem := &it.pool.elements[it.idx]
    it.idx += it.dir

    return elem, true
}