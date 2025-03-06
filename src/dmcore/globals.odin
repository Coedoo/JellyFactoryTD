package dmcore

import "core:fmt"


// @(export)
// UpdateStatePointer : UpdateStatePointerFunc : proc(platformPtr: ^Platform) {
//     platform = platformPtr

//     input     = &platformPtr.input
//     time      = &platformPtr.time
//     renderCtx = platformPtr.renderCtx
//     audio     = &platformPtr.audio
//     // mui       = platformPtr.mui
//     assets    = &platformPtr.assets
//     uiCtx     = &platformPtr.uiCtx

//     fmt.println("Setting state pointers")

//     // for k, v in assets.assetsMap {
//     //     fmt.println(k, v)
//     // }
// }