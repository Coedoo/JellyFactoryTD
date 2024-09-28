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
    layoutStacks: [dynamic]Layout,
    defaultLayout: Layout,
    panelLayout: Layout,
    textLayout: Layout,
    buttonLayout: Layout,

    // Styles
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

    Clickable,
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

    isFloating: bool,

    text: string,
    textSize: v2,

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
        bgColor = {0.3, 0.3, 0.3, 1},

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

PushParent :: proc {
    PushParentText,
    PushParentNode,
}

PushParentText :: proc(text: string) -> ^UINode {
    node := AddNode(text, {})
    PushParentNode(node)

    return node
}

PushParentNode :: proc(parent: ^UINode) {
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

            // if axis == .X {
            //     node.targetSize.x += PADDING_LEFT + PADDING_RIGHT
            // }
            // else {
            //     node.targetSize.y += PADDING_TOP + PADDING_BOT
            // }
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

    for i in 0..=1 {
        axis := LayoutAxis(i)
        if violation[i] > 0 {
            if axis == node.childrenAxis {
                for child := node.firstChild; child != nil; child = child.nextSibling {
                    toRemove := child.targetSize[i] * (1 - child.preferredSize[axis].strictness)
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
    if node.childrenAxis == .X {
        childPos: f32 = node.targetPos.x
        for next := node.firstChild; next != nil; next = next.nextSibling {
            if next.isFloating == false {
                next.targetPos.x = childPos
                next.targetPos.y = node.targetPos.y
            }

            childPos += next.targetSize.x + f32(node.spacing)
        }
    }
    else {
        childPos: f32 = node.targetPos.y

        for next := node.firstChild; next != nil; next = next.nextSibling {
            if next.isFloating == false {
                switch node.childrenAligment.x {
                case .Left:
                    next.targetPos.x = node.targetPos.x
                case .Middle: 
                    next.targetPos.x = node.targetPos.x + (node.targetSize.x - next.targetSize.x) / 2
                case .Right:
                    next.targetPos.x = node.targetPos.x + (node.targetSize.x - next.targetSize.x)
                }


                next.targetPos.y = childPos
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

@(deferred_in=EndLayout)
BeginLayout :: proc(
    axis:= LayoutAxis.X,
) -> bool
{
    // text := fmt.tprint("Horizontal::", loc.procedure, loc.line, sep="")
    node := AddNode("text", {})
    node.layout = uiCtx.defaultLayout

    node.preferredSize[.X] = {.Children, 0, 1}
    node.preferredSize[.Y] = {.Children, 0, 1}

    node.childrenAxis = axis

    PushParent(node)

    return true
}

EndLayout :: proc(axis := LayoutAxis.X,) {
    PopParent()
}

UIBegin :: proc(uiCtx: ^UIContext, screenWidth, screenHeight: int) {
    #reverse for &node, i in uiCtx.nodes {
        if node.touchedThisFrame == false {
            unordered_remove(&uiCtx.nodes, i)
        }

        node.touchedThisFrame = false
    }

    free_all(uiCtx.transientAllocator)

    root := AddNode("root", {})
    root.isFloating = true
    root.targetSize = {f32(screenWidth), f32(screenHeight)}

    PushParent(root)
}

UIEnd :: proc() {
    PopParent()

    uiCtx.hotId = uiCtx.nextHot

    assert(len(uiCtx.parentStack) == 0)
    assert(len(uiCtx.hashStack) == 0)

    DoLayout()
}

GetNode :: proc(text: string) -> ^UINode {
    id := GetId(text)
    res: ^UINode
    for &node in uiCtx.nodes {
        if node.id == id {
            res = &node
            break
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

    res.text = strings.clone(text, uiCtx.transientAllocator)

    return res
}

AddNode :: proc(text: string, flags: NodeFlags) -> ^UINode {
    node := GetNode(text)
    mem.zero_item(&node.PerFrameData)

    node.flags = flags
    node.touchedThisFrame = true

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
        targetRect := Rect{node.targetPos.x, node.targetPos.y, node.targetSize.x, node.targetSize.y}
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

/////////
// Windows
/////////

UIBeginWindow :: proc(text: string, isOpen: ^bool) -> bool {
    if isOpen^ == false {
        return false 
    }

    background := AddNode(text, { .DrawBackground })
    background.layout = uiCtx.defaultLayout
    background.bgColor = MAGENTA
    background.isFloating = true

    background.childrenAxis = .Y
    background.preferredSize[.X] = {.Children, 0, 1}
    background.preferredSize[.Y] = {.Children, 0, 1}

    // SetLayout(background, .Container)
    PushParent(background)

    header := AddNode("Header", {.Clickable})
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
    label := AddNode(text, { .DrawText })
    label.style = uiCtx.textStyle
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
    node := AddNode(text, { .DrawBackground, .Clickable, .DrawText })
    node.style = uiCtx.buttonStyle
    node.layout = uiCtx.buttonLayout

    interaction := GetNodeInteraction(node)
    return bool(interaction.cursorUp)
}

UILabel :: proc(text: string) {
    node := AddNode(text, { .DrawText })
    node.style = uiCtx.textStyle
    node.layout = uiCtx.textLayout
}

///////////////////////////////

DrawNode :: proc(renderCtx: ^RenderContext, node: ^UINode) {
    nodeCenter := node.targetPos + node.targetSize / 2
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
                v2{0, 0},
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