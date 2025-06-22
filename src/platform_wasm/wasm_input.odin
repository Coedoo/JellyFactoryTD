package platform_wasm

import "core:sys/wasm/js"
import dm "../dmcore"

import "core:fmt"

JsToDMMouseButton := []dm.MouseButton {
    .Left,
    .Middle,
    .Right,
}


eventBufferOffset: int
eventsBuffer: [64]js.Event

JsKeyToKey: map[string]dm.Key

InitInput :: proc() {
    JsKeyToKey["Enter"]       = .Return
    JsKeyToKey["NumpadEnter"] = .Return
    JsKeyToKey["Escape"]      = .Esc
    JsKeyToKey["Backspace"]   = .Backspace
    JsKeyToKey["Space"]       = .Space

    JsKeyToKey["ControlLeft"]  = .LCtrl
    JsKeyToKey["ControlRight"] = .RCtrl
    JsKeyToKey["ShiftLeft"]    = .LShift
    JsKeyToKey["ShiftRight"]   = .RShift
    JsKeyToKey["AltLeft"]      = .LAlt
    JsKeyToKey["AltRight"]     = .RAlt

    JsKeyToKey["ArrowLeft"]  = .Left
    JsKeyToKey["ArrowUp"]    = .Up
    JsKeyToKey["ArrowRight"] = .Right
    JsKeyToKey["ArrowDown"]  = .Down

    JsKeyToKey["Digit0"] = .Num0
    JsKeyToKey["Digit1"] = .Num1
    JsKeyToKey["Digit2"] = .Num2
    JsKeyToKey["Digit3"] = .Num3
    JsKeyToKey["Digit4"] = .Num4
    JsKeyToKey["Digit5"] = .Num5
    JsKeyToKey["Digit6"] = .Num6
    JsKeyToKey["Digit7"] = .Num7
    JsKeyToKey["Digit8"] = .Num8
    JsKeyToKey["Digit9"] = .Num9

    JsKeyToKey["F1"] = .F1
    JsKeyToKey["F2"] = .F2
    JsKeyToKey["F3"] = .F3
    JsKeyToKey["F4"] = .F4
    JsKeyToKey["F5"] = .F5
    JsKeyToKey["F6"] = .F6
    JsKeyToKey["F7"] = .F7
    JsKeyToKey["F8"] = .F8
    JsKeyToKey["F9"] = .F9
    JsKeyToKey["F10"] = .F10
    JsKeyToKey["F11"] = .F11
    JsKeyToKey["F12"] = .F12

    JsKeyToKey["KeyA"] = .A
    JsKeyToKey["KeyB"] = .B
    JsKeyToKey["KeyC"] = .C
    JsKeyToKey["KeyD"] = .D
    JsKeyToKey["KeyE"] = .E
    JsKeyToKey["KeyF"] = .F
    JsKeyToKey["KeyG"] = .G
    JsKeyToKey["KeyH"] = .H
    JsKeyToKey["KeyI"] = .I
    JsKeyToKey["KeyJ"] = .J
    JsKeyToKey["KeyK"] = .K
    JsKeyToKey["KeyL"] = .L
    JsKeyToKey["KeyM"] = .M
    JsKeyToKey["KeyN"] = .N
    JsKeyToKey["KeyO"] = .O
    JsKeyToKey["KeyP"] = .P
    JsKeyToKey["KeyQ"] = .Q
    JsKeyToKey["KeyR"] = .R
    JsKeyToKey["KeyS"] = .S
    JsKeyToKey["KeyT"] = .T
    JsKeyToKey["KeyU"] = .U
    JsKeyToKey["KeyV"] = .V
    JsKeyToKey["KeyW"] = .W
    JsKeyToKey["KeyX"] = .X
    JsKeyToKey["KeyY"] = .Y
    JsKeyToKey["KeyZ"] = .Z

    JsKeyToKey["Numpad0"] = .Num0
    JsKeyToKey["Numpad1"] = .Num1
    JsKeyToKey["Numpad2"] = .Num2
    JsKeyToKey["Numpad3"] = .Num3
    JsKeyToKey["Numpad4"] = .Num4
    JsKeyToKey["Numpad5"] = .Num5
    JsKeyToKey["Numpad6"] = .Num6
    JsKeyToKey["Numpad7"] = .Num7
    JsKeyToKey["Numpad8"] = .Num8
    JsKeyToKey["Numpad9"] = .Num9

    JsKeyToKey["Backquote"] = .Tilde

    js.add_event_listener("game_viewport", .Mouse_Down, nil, StoreEvent)
    js.add_event_listener("game_viewport", .Mouse_Up, nil,   StoreEvent)
    js.add_event_listener("game_viewport", .Mouse_Move, nil, StoreEvent)

    js.add_event_listener("game_viewport", .Key_Down, nil, StoreEvent)
    js.add_event_listener("game_viewport", .Key_Up, nil, StoreEvent)

    js.add_event_listener("game_viewport", .Wheel, nil, StoreEvent)
}


StoreEvent :: proc(e: js.Event) {
    if eventBufferOffset < len(eventsBuffer) {
        eventsBuffer[eventBufferOffset] = e
        eventBufferOffset += 1
    }
}
