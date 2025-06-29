package game

import dm "../dmcore"
import "core:math"

// SequenceTermination :: enum {
//     Manual,
//     Input,
//     Timeout,
// }

SequenceStep :: union {
    SequenceStepCharMovement,
    SequenceStepDialog,
}

SequenceStepDialog :: struct {
    text: string,
    charTex: dm.TexHandle,
}

Character :: enum {
    Jelly
}

CharacterMove :: struct {
    char: Character,
    from, to: v2,
}

SequenceStepCharMovement :: struct {
    duration: f32,
    moves: []CharacterMove,
}

Sequence :: struct {
    currentIdx: int,
    stepTime: f32,
    steps: []SequenceStep,
}

NextStep :: proc(seq: ^Sequence) {
    seq.currentIdx += 1
    seq.stepTime = 0
}

UpdateSequence :: proc(seq: ^Sequence) {
    if seq.currentIdx >= len(seq.steps) {
        return
    }

    step := &seq.steps[seq.currentIdx]
    seq.stepTime += dm.time.deltaTime

    switch s in step {
        case SequenceStepDialog: {
            if dm.GetMouseButton(.Left) == .JustPressed {
                NextStep(seq)
            }
        }

        case SequenceStepCharMovement: {
            if seq.stepTime >= s.duration {
                NextStep(seq)
            }
        }
    }

    // Debug
    if(dm.GetKeyState(.R) == .JustPressed) {
        seq.stepTime = 0
    }

    if(dm.GetKeyState(.Num1) == .JustPressed) {
        seq.currentIdx = max(seq.currentIdx - 1, 0)
        seq.stepTime = 0
    }


    if(dm.GetKeyState(.Num2) == .JustPressed) {
        seq.currentIdx = max(seq.currentIdx + 1, 0)
        seq.stepTime = 0
    }
}

DrawSequence :: proc(seq: ^Sequence) {
    if seq.currentIdx >= len(seq.steps) {
        return
    }
    
    step := &seq.steps[seq.currentIdx]

    switch s in step {
        case SequenceStepDialog: {
            screenSize := dm.ToV2(dm.renderCtx.frameSize)

            panelHeight: f32 = 300
            layout := dm.uiCtx.panelLayout
            layout.preferredSize = {
                .X = {.Fixed, screenSize.x - 20, 1},
                .Y = {.Fixed, panelHeight - 20, 1},
            }

            style := dm.uiCtx.panelStyle
            style.fontSize = 40

            dm.NextNodeLayout(layout)
            dm.PushStyle(style)
            dm.NextNodePosition({screenSize.x / 2, screenSize.y - panelHeight / 2})
            if dm.Panel("Dialog", dm.Aligment{.Middle, .Middle}) {
                dm.UILabel(s.text)
            }
            dm.PopStyle()
        }

        case SequenceStepCharMovement: {
            spriteName := "Jelly_.png"
            atlas := dm.SpriteAtlas {
                texture = dm.GetTextureAsset(spriteName),
                cellSize = {32, 32},
            }

            p := seq.stepTime / s.duration
            for m in s.moves {
                delta := m.to - m.from
                
                animRow: i32
                flipX: bool
                if abs(delta.x) > abs(delta.y) {
                    animRow = 2
                    flipX = delta.x > 0
                }
                else {
                    animRow = delta.y > 0 ? 1 : 0
                }

                sprite := dm.GetSprite(atlas, {0, animRow})
                sprite.frames = 4
                sprite.animDirection = .Horizontal
                sprite.flipX = flipX
                dm.AnimateSprite(&sprite, seq.stepTime, 0.1)

                pos := math.lerp(m.from, m.to, p)
                dm.DrawSprite(sprite, pos)
            }
        }
    }
}

TestSequence := Sequence {
    steps = {
        SequenceStepDialog{ text = "Lorem ipsum or something"},
        SequenceStepCharMovement {
            duration = 3,
            moves = {
                {.Jelly, {1, 1}, {5, 1}},
                {.Jelly, {5, 1}, {5, 5}},
                {.Jelly, {5, 5}, {1, 5}},
                {.Jelly, {1, 5}, {1, 1}},
            }
        },
        SequenceStepDialog{ text = "YAY"},
    },
}