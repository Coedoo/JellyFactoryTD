package platform_wasm

import "core:mem"
import "base:runtime"
import dm "../dmcore"
import "core:sys/wasm/js"
import "core:fmt"

// wasmContext: runtime.Context

// // @TODO make it configurable
// tempBackingBuffer: [64 * mem.Megabyte]byte
// tempArena: mem.Arena


// WASM_MEMORY_PAGES :: #config(MLW_WASM_MEMORY_PAGES_CONFIG, 16384) // 1 GiB default

// // mainBackingBuffer: [200 * mem.Megabyte]byte
// mainAllocator: dm.Free_List

// InitContext :: proc () {
//     wasmContext = context

//     mem.arena_init(&tempArena, tempBackingBuffer[:])
//     wasmContext.temp_allocator = mem.arena_allocator(&tempArena)

//     if data, err := js.page_alloc(WASM_MEMORY_PAGES); err == .None {
//         // sj.free_list_init(&free_list, data)

//         dm.free_list_init(&mainAllocator, data)
//         wasmContext.allocator = dm.free_list_allocator(&mainAllocator)
//     }
//     else {
//         fmt.printf("Failed to allocate %v pages.", WASM_MEMORY_PAGES)
//     }

//     wasmContext.logger = context.logger
// }

@(export, link_name="wasm_alloc")
WasmAlloc :: proc "contextless" (byteLength: uint, ctx: ^runtime.Context) -> rawptr {
    context = ctx^
    rec := make([]byte, byteLength, ctx.allocator)
    return raw_data(rec)
}

@(export, link_name="wasm_temp_alloc")
WasmTempAlloc :: proc "contextless" (byteLength: uint, ctx: ^runtime.Context) -> rawptr {
    context = ctx^
    rec := make([]byte, byteLength, ctx.temp_allocator)
    return raw_data(rec)
}

// wasmContext: runtime.Context

// // @TODO make it configurable
// tempBackingBuffer: [8 * mem.Megabyte]byte
// tempArena: mem.Arena


// mainBackingBuffer: [128 * mem.Megabyte]byte
// mainArena: mem.Arena

// InitContext :: proc () {
//     // wasmContext = context

//     mem.arena_init(&tempArena, tempBackingBuffer[:])
//     wasmContext.temp_allocator = mem.arena_allocator(&tempArena)

//     mem.arena_init(&mainArena, mainBackingBuffer[:])
//     wasmContext.allocator = mem.arena_allocator(&mainArena)

//     wasmContext.logger = context.logger
// }

// @(export, link_name = "get_ctx_ptr")
// GetContextPtr :: proc "contextless" () -> (^runtime.Context) {
//     return &wasmContext
// }

// @(export, link_name="wasm_alloc")
// WasmAlloc :: proc "contextless" (byteLength: uint) -> rawptr {
//     context = wasmContext
//     rec := make([]byte, byteLength, context.allocator)
//     return raw_data(rec)
// }

// @(export, link_name="wasm_temp_alloc")
// WasmTempAlloc :: proc "contextless" (byteLength: uint) -> rawptr {
//     context = wasmContext
//     rec := make([]byte, byteLength, context.temp_allocator)
//     return raw_data(rec)
// }
