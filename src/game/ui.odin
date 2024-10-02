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

MenuState :: enum {
    Main,
    Levels,
    Options,
    Credits,
}
menuState: MenuState

GameMenu :: proc() {
    panelStyle := dm.uiCtx.panelStyle
    panelStyle.padding = {200, 200, 300, 40}

    // dm.NextNodeStyle(panelStyle)

    dm.NextNodePosition(dm.ToV2(dm.renderCtx.frameSize / 2))
    if dm.Panel("Menu") {
        style := dm.uiCtx.textStyle
        style.fontSize = 60

        dm.NextNodeStyle(style)
        dm.UILabel("Jelly vs Geometry")

        @static t1: bool
        @static t2: bool
        dm.UICheckbox("slkf", &t1)
        dm.UICheckbox("slkff", &t2)

        dm.UISpacer(50)

        style = dm.uiCtx.buttonStyle
        style.fontSize = 30
        dm.PushStyle(style)

        switch menuState {
        case .Main: 
            if dm.UIButton("Select Level") {
                menuState = .Levels
            }

            if dm.UIButton("Options") {
                menuState = .Options
            }

            if dm.UIButton("Credits") {
                menuState = .Credits
            }
        case .Levels: {
            for &level in gameState.levels {
                if dm.UIButton(level.name) {
                    OpenLevel(level.name)
                }
            }

            dm.UISpacer(50) 
            if dm.UIButton("Back") {
                menuState = .Main
            }
        }
        case .Options: {
            @static music: f32

            if dm.UISlider("Main Audio", &music, 0, 10) {
            }
            dm.UISlider("Sounds", nil, 0, 10)
            dm.UISlider("Music", nil, 0, 10)

            dm.UISpacer(50) 
            if dm.UIButton("Back") {
                menuState = .Main
            }
        }

        case .Credits: {
            dm.UILabel("Yo Mama")
            dm.UISpacer(50) 
            if dm.UIButton("Back") {
                menuState = .Main
            }
        }
        }


        dm.PopStyle()
    }

    dm.muiBeginWindow(dm.mui, "UI debug str", {600, 50, 200, 150}, {})
    dm.muiText(dm.mui, dm.CreateUIDebugString())
    dm.muiEndWindow(dm.mui)


    // dm.muiBeginWindow(dm.mui, "UI debug", {800, 50, 100, 150}, {})
    // dm.muiLabel(dm.mui, "Nodes:", len(dm.uiCtx.nodes))
    // dm.muiLabel(dm.mui, "Hot Id:", dm.uiCtx.hotId)
    // dm.muiLabel(dm.mui, "activeId:", dm.uiCtx.activeId)
    // dm.muiEndWindow(dm.mui)
}

TestUI :: proc() {
    @static windowOpen := true

    dm.muiBeginWindow(dm.mui, "UI debug", {600, 50, 100, 150}, {})
    dm.muiLabel(dm.mui, "Nodes:", len(dm.uiCtx.nodes))
    dm.muiLabel(dm.mui, "Hot Id:", dm.uiCtx.hotId)
    dm.muiLabel(dm.mui, "activeId:", dm.uiCtx.activeId)
    if windowOpen == false {
        if dm.muiButton(dm.mui, "Open Again") {
            windowOpen = true
        }
    }
    dm.muiEndWindow(dm.mui)

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