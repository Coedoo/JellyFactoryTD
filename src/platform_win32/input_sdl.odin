package main

import dm "../dmcore"
import sdl "vendor:sdl2"

SDLKeyToKey := #partial #sparse [sdl.Scancode]dm.Key {
    .A = .A,
    .B = .B,
    .C = .C,
    .D = .D,
    .E = .E,
    .F = .F,
    .G = .G,
    .H = .H,
    .I = .I,
    .J = .J,
    .K = .K,
    .L = .L,
    .M = .M,
    .N = .N,
    .O = .O,
    .P = .P,
    .R = .R,
    .S = .S,
    .T = .T,
    .Q = .Q,
    .U = .U,
    .V = .V,
    .W = .W,
    .X = .X,
    .Y = .Y,
    .Z = .Z,

    .NUM0 = .Num0,
    .NUM1 = .Num1,
    .NUM2 = .Num2,
    .NUM3 = .Num3,
    .NUM4 = .Num4,
    .NUM5 = .Num5,
    .NUM6 = .Num6,
    .NUM7 = .Num7,
    .NUM8 = .Num8,
    .NUM9 = .Num9,

    .SPACE = .Space,
    .BACKSPACE = .Backspace,
    .RETURN = .Return,
    .TAB = .Tab,
    .ESCAPE = .Esc,

    .LSHIFT = .LShift,
    .RSHIFT = .RShift,
    .LCTRL = .LCtrl,
    .RCTRL= .RCtrl,
    .LALT = .LAlt,
    .RALT = .RAlt,

    .LEFT = .Left,
    .UP = .Up,
    .RIGHT = .Right,
    .DOWN = .Down,

    .GRAVE = .Tilde
}

SDLMouseToButton := [?]dm.MouseButton {
    .Invalid,
    .Left,
    .Middle,
    .Right,
}