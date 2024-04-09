package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"
import "core:mem"

import "../ldtk"

BuildingsWindow :: proc() {
    if dm.muiBeginWindow(dm.mui, "Buildings", {10, 10, 200, 350}, {}) {
        for b, idx in Buildings {
            // sprite := gameState.buildingSprites[b.sprite]
            // dm.DrawRectSize(sprite.texture, {10, 10}, {40, 40}, origin = {0, 0})
            if dm.muiButton(dm.mui, b.name) {
                gameState.selectedBuildingIdx = idx + 1
            }
        }

        dm.muiEndWindow(dm.mui)
    }
}