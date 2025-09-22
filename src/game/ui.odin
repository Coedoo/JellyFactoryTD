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
    // dm.NextNodePosition({100, 100})
    if dm.UIBeginWindow("Buildings") {
        for b, idx in Buildings {
            tex := dm.GetTextureAsset(b.spriteName)
            // sprite := gameState.buildingSprites[b.sprite]
            dm.PushId(idx)
            if dm.ImageButton(tex, b.name) {
                gameState.selectedBuildingIdx = idx + 1
                gameState.buildUpMode = .Building
                // fmt.println("AAAAAAA")
            }
            dm.PopId()
        }

        dm.UIEndWindow()
    }
}

TestUI :: proc() {
    @static windowOpen := true

    // dm.muiBeginWindow(dm.mui, "UI debug", {600, 50, 100, 150}, {})
    // dm.muiLabel(dm.mui, "Nodes:", len(dm.uiCtx.nodes))
    // dm.muiLabel(dm.mui, "Hot Id:", dm.uiCtx.hotId)
    // dm.muiLabel(dm.mui, "activeId:", dm.uiCtx.activeId)

    // if windowOpen == false {
    //     if dm.muiButton(dm.mui, "Open Again") {
    //         windowOpen = true
    //     }
    // }
    // dm.muiEndWindow(dm.mui)

    // dm.NextNodePosition(dm.ToV2(dm.renderCtx.frameSize / 2))
    // panel := dm.AddNode("testpanel", {})
    // panel.origin = {1, 1}
    // panel.childrenAxis = .X
    // panel.preferredSize[.X] = {.Children, 0, 1}
    // panel.preferredSize[.Y] = {.Children, 0, 1}

    // panel.flags += {.AnchoredPosition}
    // panel.anchoredPosPercent = {1, 1}
    // panel.anchoredPosOffset = {-100, -50}

    dm.muiBeginWindow(dm.mui, "UI debug str", {600, 50, 200, 150}, {})
    dm.muiText(dm.mui, dm.CreateUIDebugString())
    dm.muiEndWindow(dm.mui)


    // dm.PushParent(panel)

    // if dm.UIContainer("container", .TopCenter, layoutAxis = .Y) {
    //     dm.UIImage(gameState.playerSprite.texture, idIdx = 0)
    //     dm.UIImage(gameState.arrowSprite.texture)
    //     dm.UIImage(gameState.playerSprite.texture, idIdx = 1)
    // }

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

            if dm.LayoutBlock("Labels", axis)
            {
                dm.UILabel("Label1")
                dm.UILabel("Label2")
                dm.UILabel("Label3")
                dm.UILabel("Label6")
            }
        }
        
        dm.UIImage(gameState.playerSprite.texture)

        dm.UILabel("Label AAAAA")
        dm.UILabel("Label AAAAAAA")
        dm.UILabel("A")
        dm.UILabel("B")


        dm.UIEndWindow()
    }

}