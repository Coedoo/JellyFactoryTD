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

TestUI :: proc() {
    @static windowOpen := true

    // muiBeginWindow(mui, "UI debug", {600, 50, 100, 150}, {})
    // muiLabel(mui, "Nodes:", len(gameState.uiCtx.nodes))
    // muiLabel(mui, "Hot Id:", gameState.uiCtx.hotId)
    // muiLabel(mui, "activeId:", gameState.uiCtx.activeId)
    // if windowOpen == false {
    //     if muiButton(mui, "Open Again") {
    //         windowOpen = true
    //     }
    // }
    // muiEndWindow(mui)


    if dm.UIBeginWindow("Window", &windowOpen) {
        @static toggle: bool = true
        if dm.UIButton("Button") {
            toggle = !toggle
        }
        
        if toggle {
            @static switchAxis: bool = true
            if dm.UIButton( "Switch Layout") {
                switchAxis = !switchAxis
            }

            axis: dm.LayoutAxis = .X if switchAxis else .Y
            dm.UILabel("Layout Axis:")

            if dm.BeginLayout(axis)
            {
                dm.UILabel("Label1")
                dm.UILabel("Label2")
                dm.UILabel("Label3")
            }
        }
        
        dm.UILabel("Label AAAAA")
        dm.UILabel("Label AAAAAAA")


        dm.UIEndWindow()
    }

}