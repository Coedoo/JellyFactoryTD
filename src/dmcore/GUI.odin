package dmcore

import "core:mem"

import "core:math"
import "core:math/linalg/glsl"
import "core:fmt"
import mu "vendor:microui"

import "core:strings"

/////////
// Context management
/////////

Id :: distinct u32

UIContext :: struct {
    transientArena: mem.Arena,
    transientAllocator: mem.Allocator,

    nodes: [dynamic]UINode,

    hotId: Id,
    activeId: Id,

    nextHot: Id,

    hashStack: [dynamic]Id,
    parentStack: [dynamic]^UINode,

    // Layout
    popLayoutAfterUse: bool,
    layoutStack: [dynamic]Layout,
    
    defaultLayout: Layout,
    panelLayout: Layout,
    textLayout: Layout,
    buttonLayout: Layout,

    nextNodePos: Maybe(v2),
    nextNodeOrigin: Maybe(v2),

    // Styles
    popStyleAfterUse: bool,
    stylesStack: [dynamic]Style,

    defaultStyle: Style,
    panelStyle: Style,
    textStyle: Style,
    buttonStyle: Style,
}

/////////
// Nodes
/////////

NodeFlag :: enum {
    DrawBackground,
    DrawText,
    BackgroundTexture,

    Clickable,

    FloatingX,
    FloatingY,
}
NodeFlags :: distinct bit_set[NodeFlag]

UINode :: struct {
    using PerFrameData : struct {
        parent: ^UINode,

        firstChild:  ^UINode,
        lastChild:   ^UINode,
        prevSibling: ^UINode,
        nextSibling: ^UINode,
        childrenCount: int,

        touchedThisFrame: bool,

        flags: NodeFlags,

        // childrenAxis: LayoutAxis,
        // childrenAligment: Aligment,
        // preferredSize: [LayoutAxis]NodePreferredSize,
    },

    id: Id,

    text: string,
    textSize: v2,

    texture: TexHandle,
    textureSource: UIRect,

    origin: v2,
    targetPos: v2,
    targetSize: v2,

    using style: Style,
    using layout: Layout,
}

UINodeInteraction :: struct {
    cursorDown: b8,
    cursorPressed: b8,
    cursorUp: b8
}

ControlStyle :: enum {
    None,
    Container,
    Button,
    Label,
}

/////////
// Style
/////////
LayoutAxis :: enum {
    X,
    Y,
}

NodeSizeType :: enum {
    None,
    Fixed,
    Text,
    Children,
    ParentPercent
}

NodePreferredSize :: struct {
    type: NodeSizeType,
    value: f32,
    strictness: f32,
}

AligmentX :: enum {
    Left, Middle, Right,
}
AligmentY :: enum {
    Top, Middle, Bottom,
}
Aligment :: struct {
    y: AligmentY,
    x: AligmentX,
}

UIRect :: struct {
    left, right: int,
    top, bot: int,
}

Style :: struct {
    font: Font,
    fontSize: int,

    textColor: color,
    bgColor: color,

    hotColor: color,
    activeColor: color,

    padding: UIRect,
}

Layout :: struct {
    childrenAxis: LayoutAxis,
    childrenAligment: Aligment,

    spacing: int,

    preferredSize: [LayoutAxis]NodePreferredSize,
}

InitUI :: proc(uiCtx: ^UIContext, renderCtx: ^RenderContext) {
    memory := make([]byte, mem.Megabyte)
    mem.arena_init(&uiCtx.transientArena, memory)
    uiCtx.transientAllocator = mem.arena_allocator(&uiCtx.transientArena)

    uiCtx.nodes = make([dynamic]UINode, 0, 1024)
    uiCtx.stylesStack = make([dynamic]Style, 0, 32)

    font := LoadDefaultFont(renderCtx)
    uiCtx.defaultStyle = {
        font = font,
        fontSize = 18,

        textColor = {1, 1, 1, 1},
        bgColor = {1, 1, 1, 1},

        hotColor = {0.4, 0.4, 0.4, 1},
        activeColor = {0.6, 0.6, 0.6, 1},

        padding = {3, 3, 3, 3},
    }

    uiCtx.defaultLayout = {
        childrenAxis = .Y,
        childrenAligment = { .Top, .Left },

        spacing = 5,

        preferredSize = {.X = {.Fixed, 100, 1},  .Y = {.Fixed,    30, 1}}
    }

    uiCtx.panelStyle = uiCtx.defaultStyle
    uiCtx.panelStyle.bgColor = {0.3, 0.3, 0.3, 0.5}

    uiCtx.panelLayout = uiCtx.defaultLayout
    uiCtx.panelLayout.childrenAligment = {.Middle, .Middle}
    uiCtx.panelLayout.preferredSize = {.X = {.Children, 0, 1}, .Y = {.Children, 0, 1}}

    uiCtx.textStyle = uiCtx.defaultStyle
    uiCtx.textLayout = uiCtx.defaultLayout
    uiCtx.textLayout.preferredSize = {.X = {.Text, 0, 0.2}, .Y = {.Text, 0, 0.2}}

    uiCtx.buttonStyle = uiCtx.defaultStyle
    uiCtx.buttonStyle.bgColor = {1, 0.1, 0.3, 1}
    uiCtx.buttonStyle.hotColor = {1, 0.3, 0.5, 1}
    uiCtx.buttonStyle.activeColor = {1, 0.5, 0.6, 1}

    uiCtx.buttonLayout = uiCtx.defaultLayout
    uiCtx.buttonLayout.preferredSize = {.X = {.Text, 0, 1}, .Y = {.Text, 0, 1}}
}

PushParent :: proc(parent: ^UINode) {
    append(&uiCtx.parentStack, parent)
    append(&uiCtx.hashStack, parent.id)
}

PopParent :: proc() {
    pop(&uiCtx.parentStack)
    pop(&uiCtx.hashStack)
}

PushId :: proc {
    PushIdBytes,
    PushIdStr,
    PushIdPtr,
}

PushIdPtr :: proc(ptr: rawptr) {
    PushIdBytes(([^]byte)(ptr)[:size_of(ptr)])
}

PushIdStr :: proc(str: string) {
    // @Note: I believe this doesn't transmute content of the string
    // but only pointer + length
    PushIdBytes(transmute([]byte) str)
}

PushIdBytes :: proc(bytes: []byte) {
    id := GetIdBytes(bytes)
    append(&uiCtx.hashStack, id)
}

PopId :: proc() {
    pop(&uiCtx.hashStack);
}

GetId :: proc {
    GetIdPtr,
    GetIdStr,
    GetIdBytes,
}

GetIdPtr :: proc(ptr: rawptr) -> Id {
    return GetIdBytes(([^]byte)(ptr)[:size_of(ptr)])
}

GetIdStr :: proc(str: string) -> Id {
    return GetIdBytes(transmute([]byte) str)
}

GetIdBytes :: proc(bytes: []byte) -> Id {
    /* 32bit fnv-1a hash */
    HASH_INITIAL :: 2166136261
    hash :: proc(hash: ^Id, data: []byte) {
        size := len(data)
        cptr := ([^]u8)(raw_data(data))
        for ; size > 0; size -= 1 {
            hash^ = Id(u32(hash^) ~ u32(cptr[0])) * 16777619
            cptr = cptr[1:]
        }
    }

    prev := uiCtx.hashStack[len(uiCtx.hashStack) - 1] if len(uiCtx.hashStack) != 0 else HASH_INITIAL
    hash(&prev, bytes)

    return prev
}

DoLayoutParentPercent :: proc(node: ^UINode) {
    for axis in LayoutAxis {
        size := node.preferredSize[axis]

        if size.type == .ParentPercent {
            node.targetSize[axis] = node.parent.targetSize[axis] * size.value
        }
    }

    for next := node.firstChild; next != nil; next = next.nextSibling {
        DoLayoutParentPercent(next)
    }
}

DoLayoutChildren :: proc(node: ^UINode) {
    for next := node.firstChild; next != nil; next = next.nextSibling {
        DoLayoutChildren(next)
    }

    for axis in LayoutAxis {
        size := node.preferredSize[axis]

        if size.type == .Children {
            node.targetSize[axis] = 0 
            for next := node.firstChild; next != nil; next = next.nextSibling {
                if axis == node.childrenAxis {
                    node.targetSize[axis] += next.targetSize[axis]
                }
                else {
                    node.targetSize[axis] = max(node.targetSize[axis], next.targetSize[axis])
                }
            }

            // @NOTE @TODO: I'm sure this can be done better
            if axis == node.childrenAxis {
                node.targetSize[axis] += f32(node.childrenCount - 1) * f32(node.spacing)
            }

            if axis == .X {
                node.targetSize.x += f32(node.padding.left + node.padding.right)
            }
            else {
                node.targetSize.y += f32(node.padding.top + node.padding.bot)
            }
        }
    }
}

ResolveLayoutContraints :: proc(node: ^UINode) {

    maxSize := node.targetSize
    childrenSize: v2
    childrenMinSize: v2

    for child := node.firstChild; child != nil; child = child.nextSibling {
        childrenSize += child.targetSize
        childrenMinSize.x += child.targetSize.x * (1 - child.preferredSize[.X].strictness)
        childrenMinSize.y += child.targetSize.y * (1 - child.preferredSize[.Y].strictness)
    }
    childrenSize[node.childrenAxis] += f32(node.childrenCount - 1) * f32(node.spacing)
    
    violation := childrenSize - maxSize

    // @TODO: what to do when childrenMinSize == 0?
    for i in 0..=1 {
        axis := LayoutAxis(i)
        if violation[i] > 0 {
            if axis == node.childrenAxis {
                for child := node.firstChild; child != nil; child = child.nextSibling {
                    toRemove := child.targetSize[i] * (1 - child.preferredSize[axis].strictness)

                    if toRemove == 0 {
                        continue
                    }

                    scaledRemove :=  violation[i] * (toRemove / childrenMinSize[i])
                    child.targetSize[i] -= scaledRemove
                }
            }
            else {
                for child := node.firstChild; child != nil; child = child.nextSibling {
                    if child.targetSize[i] > maxSize[i] {
                        child.targetSize[i] = maxSize[i]
                    }
                }
            }
        }
    }


    for next := node.firstChild; next != nil; next = next.nextSibling {
        ResolveLayoutContraints(next)
    }
}

DoFinalLayout :: proc(node: ^UINode) {
    nodePos := node.targetPos - node.targetSize * node.origin
    if node.childrenAxis == .X {
        childPos: f32 = nodePos.x + f32(node.padding.left)
        for next := node.firstChild; next != nil; next = next.nextSibling {
            if .FloatingX not_in next.flags {
                next.targetPos.x = childPos
            }

            if .FloatingY not_in next.flags {
                switch node.childrenAligment.y {
                case .Top:
                    next.targetPos.y = nodePos.y
                    next.targetPos.y += f32(node.padding.top)
                case .Middle:
                    sizeWithoutPadding := node.targetSize.y - f32(node.padding.top + node.padding.bot)
                    next.targetPos.y = nodePos.y + (sizeWithoutPadding - next.targetSize.y) / 2
                    next.targetPos.y += f32(node.padding.bot)
                case .Bottom:
                    next.targetPos.y = nodePos.y + (node.targetSize.y - next.targetSize.y)
                    next.targetPos.y -= f32(node.padding.bot)
                }
            }

            childPos += next.targetSize.x + f32(node.spacing)
        }
    }
    else {
        childPos: f32 = nodePos.y + f32(node.padding.top)

        for next := node.firstChild; next != nil; next = next.nextSibling {

            if .FloatingY not_in next.flags {
                next.targetPos.y = childPos
            }

            if .FloatingX not_in next.flags {
                switch node.childrenAligment.x {
                case .Left:
                    next.targetPos.x = nodePos.x
                    next.targetPos.x += f32(node.padding.left)
                case .Middle:
                    sizeWithoutPadding := node.targetSize.x - f32(node.padding.left + node.padding.right)
                    next.targetPos.x = nodePos.x + (sizeWithoutPadding - next.targetSize.x) / 2
                    next.targetPos.x += f32(node.padding.left)
                case .Right:
                    next.targetPos.x = nodePos.x + (node.targetSize.x - next.targetSize.x)
                    next.targetPos.x -= f32(node.padding.right)
                }
            }

            childPos += next.targetSize.y + f32(node.spacing)
        }
    }

    for next := node.firstChild; next != nil; next = next.nextSibling {
        DoFinalLayout(next)
    }
}

DoLayout :: proc() {
    for &node in uiCtx.nodes {
        for size, i in node.preferredSize {
            if size.type == .Fixed {
                node.targetSize[i] = node.preferredSize[i].value
            }
        }

        if node.preferredSize[.X].type == .Text ||
           node.preferredSize[.Y].type == .Text
        {
            node.textSize = MeasureText(node.text, node.font, node.fontSize)
            paddedSize := v2 {
                f32(node.padding.left + node.padding.right),
                f32(node.padding.top + node.padding.bot),
            }

            for size, i in node.preferredSize {
                if size.type == .Text {
                    node.targetSize[i] = f32(node.textSize[i]) + paddedSize[i]
                }
            }
        }
    }

    DoLayoutParentPercent(&uiCtx.nodes[0])
    DoLayoutChildren(&uiCtx.nodes[0])
    ResolveLayoutContraints(&uiCtx.nodes[0])
    DoFinalLayout(&uiCtx.nodes[0])
}

NextNodeStyle :: proc(style: Style) {
    append(&uiCtx.stylesStack, style)
    uiCtx.popStyleAfterUse = true
}

NextNodeLayout :: proc(layout: Layout) {
    append(&uiCtx.layoutStack, layout)
    uiCtx.popLayoutAfterUse = true
}

PushStyle :: proc(style: Style) {
    append(&uiCtx.stylesStack, style)
}

PopStyle :: proc() {
    pop(&uiCtx.stylesStack)
}

@(deferred_none=EndLayout)
BeginLayout :: proc(
    axis:= LayoutAxis.X,
    aligmentX := AligmentX.Middle,
    aligmentY := AligmentY.Middle,
    loc := #caller_location
) -> bool
{
    node := AddNode("", {}, uiCtx.defaultStyle, uiCtx.defaultLayout)

    node.preferredSize[.X] = {.Children, 0, 1}
    node.preferredSize[.Y] = {.Children, 0, 1}

    node.childrenAligment = { aligmentY, aligmentX }
    node.childrenAxis = axis

    PushParent(node)

    return true
}

EndLayout :: proc() {
    PopParent()
}

UIBegin :: proc(uiCtx: ^UIContext, screenWidth, screenHeight: int) {
    #reverse for &node, i in uiCtx.nodes {
        if node.touchedThisFrame == false || node.id == 0 {
            unordered_remove(&uiCtx.nodes, i)
        }

        node.touchedThisFrame = false
    }

    free_all(uiCtx.transientAllocator)

    root := AddNode("root", {}, uiCtx.defaultStyle, uiCtx.defaultLayout)
    root.preferredSize = {.X = {.Fixed, f32(screenWidth), 1}, .Y = {.Fixed, f32(screenHeight), 1}}

    PushParent(root)
}

UIEnd :: proc() {
    PopParent()

    uiCtx.hotId = uiCtx.nextHot

    assert(len(uiCtx.parentStack) == 0)
    assert(len(uiCtx.hashStack) == 0)

    DoLayout()
}

NextNodePosition :: proc(pos: v2, origin := v2{0.5, 0.5}) {
    uiCtx.nextNodePos = pos
    uiCtx.nextNodeOrigin = origin
}

GetNode :: proc(text: string) -> ^UINode {
    id: Id
    res: ^UINode

    idStr: string
    textStr: string

    idIdx := strings.index(text, "##")
    if idIdx != -1 {
        ok: bool
        idStr, ok = strings.substring(text, idIdx + 2, len(text))
        assert(ok)

        textStr, ok = strings.substring(text, 0, idIdx)
        assert(ok)
    }
    else {
        idStr = text
        textStr = text
    }

    if text != "" {
        id = GetId(idStr)
        for &node in uiCtx.nodes {
            if node.id == id {
                res = &node
                break
            }
        }
    }

    if res == nil {
        node := UINode {
            id = id,
        }

        assert(len(uiCtx.nodes) + 1 < cap(uiCtx.nodes))
        append(&uiCtx.nodes, node)
        res = &uiCtx.nodes[len(uiCtx.nodes) - 1]
    }

    res.text = textStr

    return res
}

AddNode :: proc(text: string, flags: NodeFlags, 
    style := uiCtx.defaultStyle,
    layout := uiCtx.defaultLayout) -> ^UINode
{
    node := GetNode(text)
    mem.zero_item(&node.PerFrameData)

    if len(uiCtx.stylesStack) > 0 {
        node.style = uiCtx.stylesStack[len(uiCtx.stylesStack) - 1]
        if uiCtx.popStyleAfterUse {
            pop(&uiCtx.stylesStack)
            uiCtx.popStyleAfterUse = false
        }
    }
    else {
        node.style = style
    }

    if len(uiCtx.layoutStack) > 0 {
        node.layout = uiCtx.layoutStack[len(uiCtx.layoutStack) - 1]
        if uiCtx.popLayoutAfterUse {
            pop(&uiCtx.layoutStack)
            uiCtx.popLayoutAfterUse = false
        }
    }
    else {
        node.layout = layout
    }

    node.flags = flags
    node.touchedThisFrame = true

    if pos, ok := uiCtx.nextNodePos.?; ok {
        node.flags += { .FloatingX, .FloatingY }
        node.targetPos = pos

        uiCtx.nextNodePos = nil
    }

    if origin, ok := uiCtx.nextNodeOrigin.?; ok {
        node.origin = origin

        uiCtx.nextNodeOrigin = nil
    }

    if len(uiCtx.parentStack) != 0 {
        parent := uiCtx.parentStack[len(uiCtx.parentStack) - 1]

        if parent.firstChild == nil {
            parent.firstChild = node
        }

        node.prevSibling = parent.lastChild
        if parent.lastChild != nil {
            parent.lastChild.nextSibling = node
        }

        parent.lastChild = node

        node.parent = parent
        parent.childrenCount += 1
    }

    return node
}

GetNodeInteraction :: proc(node: ^UINode) -> (result: UINodeInteraction) {
    if .Clickable in node.flags {
        targetRect := Rect{
            node.targetPos.x - node.targetSize.x * node.origin.x,
            node.targetPos.y - node.targetSize.y * node.origin.y,
            node.targetSize.x,
            node.targetSize.y}
        isMouseOver := IsPointInsideRect(ToV2(input.mousePos), targetRect)

        if uiCtx.activeId == node.id {
            result.cursorPressed = true
        }

        if isMouseOver {
            if uiCtx.activeId == 0 {
                uiCtx.nextHot = node.id
            }

            if uiCtx.hotId == node.id {
                lmb := GetMouseButton(.Left)
                if lmb == .JustPressed {
                    result.cursorDown = true
                    uiCtx.activeId = node.id
                }
                if lmb == .JustReleased && uiCtx.activeId == node.id {
                    result.cursorUp = true
                    uiCtx.activeId = 0
                }
            }
        }
        else {
            if uiCtx.hotId == node.id && uiCtx.activeId == 0 {
                uiCtx.nextHot = 0
            }
        }

        lmb := GetMouseButton(.Left)
        if lmb == .Up {
            if uiCtx.activeId == node.id {
                uiCtx.activeId = 0
                uiCtx.nextHot = 0
            }
        }
    
    }

    return
}

@(deferred_none=EndPanel)
Panel :: proc(text: string) -> bool {
    node := AddNode(text, {.DrawBackground}, uiCtx.panelStyle, uiCtx.panelLayout)

    PushParent(node)

    return true
}

EndPanel :: proc() {
    PopParent()
}

/////////
// Windows
/////////

UIBeginWindow :: proc(text: string, isOpen: ^bool) -> bool {
    if isOpen^ == false {
        return false 
    }

    background := AddNode(
        text, 
        { .DrawBackground, .FloatingX, .FloatingY }, 
        uiCtx.defaultStyle, uiCtx.defaultLayout
    )
    background.bgColor = MAGENTA

    background.childrenAxis = .Y
    background.preferredSize[.X] = {.Children, 0, 1}
    background.preferredSize[.Y] = {.Children, 0, 1}

    // SetLayout(background, .Container)
    PushParent(background)

    header := AddNode("Header", {.Clickable}, uiCtx.defaultStyle, uiCtx.defaultLayout)
    header.preferredSize[.X] = {.ParentPercent, 1, 1}
    header.preferredSize[.Y] = {.Children, 0, 1}
    header.childrenAxis = .X
    // header.isFloating = true

    interaction := GetNodeInteraction(header)
    if interaction.cursorPressed {
        background.targetPos += ToV2(input.mouseDelta)
        // fmt.println(background.targetPos)
    }

    PushParent(header)

    // UILabel(text)
    label := AddNode(text, { .DrawText }, uiCtx.textStyle, uiCtx.defaultLayout)
    label.preferredSize[.X] = {.Text, 1, 1}
    label.preferredSize[.Y] = {.Text, 1, 1}

    spacer := AddNode("Spacer", {})
    spacer.preferredSize[.X] = {.ParentPercent, 1, 0}
    spacer.preferredSize[.Y] = {.ParentPercent, 1, 0}

    // TODO: close button
    if UIButton("X") {
        isOpen^ = false
    }
    PopParent()


    return true
}

UIEndWindow :: proc() {
    PopParent()
}

/////////
// Controls
/////////

UIButton :: proc(text: string) -> bool {
    node := AddNode(text, 
        { .DrawBackground, .Clickable, .DrawText },
        style = uiCtx.buttonStyle,
        layout = uiCtx.buttonLayout)

    interaction := GetNodeInteraction(node)
    return bool(interaction.cursorUp)
}

UILabel :: proc(text: string) {
    node := AddNode(text, { .DrawText }, uiCtx.textStyle, uiCtx.textLayout)
}

UIImage :: proc(image: TexHandle, maybeSize: Maybe(iv2) = nil) {
    node := AddNode(fmt.tprint("Tex", image), {.BackgroundTexture})

    node.texture = image

    size: v2
    if pSize, ok := maybeSize.?; ok {
        size = ToV2(pSize)
    }
    else {
        size = ToV2(GetTextureSize(image))
    }

    node.preferredSize[.X] = {.Fixed, size.x, 1}
    node.preferredSize[.Y] = {.Fixed, size.y, 1}
}

UISpacer :: proc(size: int) {
    layout: Layout
    layout.preferredSize = {
        .X = {.Fixed, f32(size), 1},
        .Y = {.Fixed, f32(size), 1}
    }
    node := AddNode("", {}, {}, layout)
}

UISlider :: proc(text: string, value: ^f32, min, max: f32) -> (res: bool) {
    if BeginLayout(axis = .X) {
        label := AddNode(text, { .DrawText }, uiCtx.textStyle, uiCtx.textLayout)
        label.preferredSize[.X] = {.Fixed, 200, 0}

        slideArea := AddNode(fmt.tprint("slide", text), { .DrawBackground })
        slideArea.bgColor = {1, 1, 1, 1}
        slideArea.preferredSize[.X] = {.Fixed, 250, 0}
        slideArea.preferredSize[.Y] = {.Fixed, 5, 1}

        PushParent(slideArea)

        handle := AddNode(fmt.tprint("handle", text), {.DrawBackground, .Clickable, .FloatingX})
        handle.origin = {0.5, 0.5}
        interaction := GetNodeInteraction(handle)

        left := slideArea.targetPos.x
        right := slideArea.targetPos.x + slideArea.targetSize.x

        if value != nil {
            normalizedValue := (value^ - min) / (max - min)
            handle.targetPos.x = glsl.lerp(left, right, normalizedValue)
        }
        else {
            handle.targetPos.x = left
        }

        if interaction.cursorPressed {
            res = input.mouseDelta != {}

            handle.targetPos = ToV2(input.mousePos)
            handle.targetPos.x = clamp(handle.targetPos.x, left, right)

            if value != nil {
                normalized := ((handle.targetPos.x - left) / (right - left))
                value^ = glsl.lerp(min, max, normalized)
            }
        }

        handle.bgColor = {0, 0, 0, 1}
        handle.preferredSize[.X] = {.Fixed, 16, 1}
        handle.preferredSize[.Y] = {.Fixed, 30, 1}

        PopParent()
    }

    return
}

UICheckbox :: proc(text: string, value: ^bool) -> (res: bool) {
    if BeginLayout(axis = .X) {
        checkbox := AddNode(fmt.tprint("X##", text), {.DrawBackground, .Clickable})
        checkbox.preferredSize[.X] = {.Fixed, 25, 1}
        checkbox.preferredSize[.Y] = {.Fixed, 25, 1}
        checkbox.textColor = {0, 0, 0, 1}

        PushParent(checkbox)
        check := AddNode(fmt.tprint("check##", text), {})
        check.bgColor = {0, 0, 0, 1}
        check.preferredSize[.X] = {.ParentPercent, 1, 1}
        check.preferredSize[.Y] = {.ParentPercent, 1, 1}

        if value^ do check.flags += {.DrawBackground}
        
        PopParent()

        interaction := GetNodeInteraction(checkbox)
        if interaction.cursorUp {
            value^ = !value^
            res = true
        }

        label := AddNode(text, { .DrawText }, uiCtx.textStyle, uiCtx.textLayout)
        label.preferredSize[.X] = {.Fixed, 200, 0}
    }

    return
}

///////////////////////////////

DrawNode :: proc(renderCtx: ^RenderContext, node: ^UINode) {
    nodeCenter := node.targetPos + node.targetSize / 2 - node.targetSize * node.origin
    DrawBox2D(renderCtx, nodeCenter, node.targetSize, true)

    if .DrawBackground in node.flags {
        color := node.bgColor

        if node.id == uiCtx.activeId {
            color = node.hotColor
        }
        else if node.id == uiCtx.hotId {
            color = node.activeColor
        }

        DrawRect(
                renderCtx, 
                node.targetPos,
                node.targetSize,
                node.origin,
                color
            )
    }

    if .BackgroundTexture in node.flags {
        color := node.bgColor

        if node.id == uiCtx.activeId {
            color = node.hotColor
        }
        else if node.id == uiCtx.hotId {
            color = node.activeColor
        }

        DrawRect(
            node.texture,
            node.targetPos,
            node.targetSize,
            node.origin,
            color
        )
    }

    if .DrawText in node.flags {
        pos := node.targetPos + (node.targetSize - node.textSize) / 2
        DrawText(
            renderCtx,
            node.text,
            node.font,
            pos,
            node.fontSize,
            color = node.textColor,
        )
    }

    for next := node.firstChild; next != nil; next = next.nextSibling {
        DrawNode(renderCtx, next)
    }
}

DrawUI :: proc(renderCtx: ^RenderContext) {
    if len(uiCtx.nodes) > 0 {
        DrawNode(renderCtx, &uiCtx.nodes[0])
    }
}

CreateUIDebugString :: proc() -> string {
    b: strings.Builder
    strings.builder_init(&b, allocator = context.temp_allocator)

    PrintNode :: proc(node: UINode, builder: ^strings.Builder, indent: ^int) {
        for i in 0..<indent^ {
            fmt.sbprint(builder, "    ")
        }
        fmt.sbprintln(builder, "-", node.text, node.id)

        indent^ += 1
        for child := node.firstChild; child != nil; child = child.nextSibling {
            PrintNode(child^, builder, indent)
        }
        indent^ -= 1
    }

    indent := 0
    PrintNode(uiCtx.nodes[0], &b, &indent)

    return strings.to_string(b)
}