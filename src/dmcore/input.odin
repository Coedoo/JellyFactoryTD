package dmcore

InputState :: enum {
    Up,
    Down,
    JustPressed,
    JustReleased,
}

InputStateSet :: bit_set[InputState]

MouseButton :: enum {
    Invalid,
    Left,
    Middle,
    Right,
}

// @NOTE: it's not completed
Key :: enum {
    UNKNOWN,
    A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, R, S, T, Q, U, V, W, X, Y, Z,
    Num0, Num1, Num2, Num3, Num4, Num5, Num6, Num7, Num8, Num9,
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
    Space, Backspace, Return, Tab, Esc,
    LShift, RShift, LCtrl, RCtrl, LAlt, RAlt,
    Left, Right, Up, Down,
    Tilde
}

Input :: struct {
    key: [Key]InputStateSet,

    mousePos:   iv2,
    mouseDelta: iv2,

    scroll: int,
    scrollX: int,

    mouseKey: [MouseButton]InputStateSet,

    runesCount: int,
    runesBuffer: [16]rune,
}

GetKeyState :: proc(key: Key) -> InputState {
    if .JustPressed in input.key[key] {
        return .JustPressed
    }
    else if .JustReleased in input.key[key] {
        return .JustReleased
    }
    else if .Down in input.key[key] {
        return .Down
    }
    else {
        return .Up
    }
}

GetMouseButton :: proc(btn: MouseButton) -> InputState {
    if .JustPressed in input.mouseKey[btn] {
        return .JustPressed
    }
    else if .JustReleased in input.mouseKey[btn] {
        return .JustReleased
    }
    else if .Down in input.mouseKey[btn] {
        return .Down
    }
    else {
        return .Up
    }
}

GetAxis :: proc(left: Key, right: Key) -> f32 {
    return GetAxisCtx(input, left, right)
}

GetAxisCtx :: proc(input: ^Input, left: Key, right: Key) -> f32 {
    if GetKeyState(left) == .Down {
        return -1
    }
    else if GetKeyState(right) == .Down {
        return 1
    }

    return 0
}

GetAxisInt :: proc(left: Key, right: Key, state: InputState = .Down) -> i32 {
    if GetKeyState(left) == state {
        return -1
    }
    else if GetKeyState(right) == state {
        return 1
    }

    return 0
}

InputDebugWindow :: proc(input: ^Input, mui: ^Mui) {
    // if muiBeginWindow(mui, "Input", {0, 0, 100, 200}, nil) {

    //     muiLabel(mui, input.mousePrev)
    //     muiLabel(mui, input.mouseCurr)

    //     for key, state in input.curr {
    //         muiLabel(mui, key, state)
    //     }

    //     muiEndWindow(mui)
    // }
}