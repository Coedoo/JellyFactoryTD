package dmcore

import "core:math"
import "core:mem"
import "core:fmt"
import "core:slice"

/// Free List Allocator

// FreeListHeader :: struct {
//     blockSize: uint,
//     padding: uint,
// }

// FreeListNode :: struct {
//     next: ^FreeListNode,
//     blockSize: uint,
// }

// FreeList :: struct {
//     data: []u8,
//     used: uint,

//     head: ^FreeListNode,
// }

// FreeListFreeAll :: proc(list: ^FreeList) {
//     list.used = 0
//     list.head = cast(^FreeListNode) raw_data(list.data)
//     list.head.blockSize = len(list.data)
//     list.head.next = nil
// }

// FreeListInit :: proc(list: ^FreeList, data: []u8) {
//     list.data = data
//     FreeListFreeAll(list)
// }

// CalcPaddingWithHeader :: proc(ptr, aligment: uintptr, headerSize: uint) -> uint {
//     modulo := ptr & (aligment - 1) // (ptr % aligment) as it assumes alignment is a power of two

//     padding: uintptr
//     if modulo != 0 {
//         padding = aligment - modulo
//     }

//     neededSpace := uintptr(headerSize)

//     if padding < neededSpace {
//         neededSpace -= padding

//         if (neededSpace & (aligment - 1)) != 0 {
//             padding += aligment * (1 + (neededSpace / aligment))
//         }
//         else {
//             padding += aligment * (neededSpace / aligment)
//         }
//     }

//     return uint(padding)
// }

// FreeListFindFirst :: proc(list: ^FreeList, size: uint, aligment: uint) -> 
//     (node:^FreeListNode, prevNode: ^FreeListNode, padding: uint)
// {
//     node = list.head

//     for node != nil {
//         nodePtr := uintptr(rawptr(node))
//         padding = CalcPaddingWithHeader(nodePtr, uintptr(aligment), size_of(FreeListHeader))

//         requiredSpace := size + padding
//         if node.blockSize >= requiredSpace {
//             break
//         }

//         prevNode = node
//         node = node.next
//     }

//     return
// }

// FreeListAlloc :: proc(list: ^FreeList, size, aligment: uint) -> uintptr {

//     aligment := aligment
//     if aligment < 8 {
//         aligment = 8
//     }

//     size := size
//     if size < size_of(FreeListNode) {
//         size = size_of(FreeListNode)
//     }

//     node, prevNode, padding := FreeListFindFirst(list, size, aligment)
//     if node == nil {
//         panic("Out of memory")
//     }

//     aligmentPadding := padding - size_of(FreeListHeader)
//     requiredSpace := size + padding
//     remaining := node.blockSize - requiredSpace

//     nodePtr := uintptr(rawptr(node))

//     if remaining > 0 {
//         newNode := cast(^FreeListNode) (nodePtr + uintptr(requiredSpace))
//         newNode.blockSize = remaining
//         FreeListNodeInsert(&list.head, node, newNode)
//     }

//     FreeListNodeRemove(&list.head, prevNode, node)

//     headerPtr := cast(^FreeListHeader)(nodePtr + uintptr(aligmentPadding))
//     headerPtr.blockSize = requiredSpace
//     headerPtr.padding = aligmentPadding

//     list.used += requiredSpace

//     return uintptr(rawptr(headerPtr)) + size_of(FreeListHeader)
// }

// FreeListFree :: proc(list: ^FreeList, ptr: rawptr) {
//     if ptr == nil {
//         return
//     }

//     header := cast(^FreeListHeader) (uintptr(ptr) - size_of(FreeListHeader))
//     freeNode := cast(^FreeListNode) header
//     freeNode.blockSize = header.blockSize + header.padding
//     freeNode.next = nil

//     prevNode: ^FreeListNode
//     node := list.head
//     for node != nil {
//         // when we find the first next node after the one
//         // we just freed, insert new free node between that
//         // and the previous one
//         if ptr < rawptr(node) {
//             FreeListNodeInsert(&list.head, prevNode, freeNode)
//             break
//         }

//         prevNode = node
//         node = node.next
//     }

//     list.used -= freeNode.blockSize
//     FreeListCoalescence(list, prevNode, freeNode)
// }

// FreeListCoalescence :: proc(list: ^FreeList, prevNode, freeNode: ^FreeListNode) {
//     if freeNode.next != nil && 
//         uintptr(rawptr(freeNode)) + uintptr(freeNode.blockSize) == uintptr(freeNode.next)
//     {
//         freeNode.blockSize += freeNode.next.blockSize
//         FreeListNodeRemove(&list.head, freeNode, freeNode.next)
//     }

//     if prevNode != nil &&
//         prevNode.next != nil && 
//         uintptr(rawptr(prevNode)) + uintptr(prevNode.blockSize) == uintptr(freeNode)
//     {
//         prevNode.blockSize += prevNode.next.blockSize
//         FreeListNodeRemove(&list.head, prevNode, freeNode)
//     }
// }

// FreeListNodeInsert :: proc(head: ^^FreeListNode, prevNode, newNode: ^FreeListNode) {
//     if prevNode == nil {
//         newNode.next = head^
//         head^ = newNode
//     }
//     else {
//         if prevNode.next == nil {
//             prevNode.next = newNode
//             newNode.next = nil
//         }
//         else {
//             newNode.next = prevNode.next
//             prevNode.next = newNode
//         }
//     }
// }

// FreeListNodeRemove :: proc(head: ^^FreeListNode, prev, deleted: ^FreeListNode) {
//     if prev == nil {
//         head^ = deleted.next
//     }
//     else {
//         prev.next = deleted.next
//     }
// }

// FreeListAllocator :: proc "contextless" (list: ^FreeList) -> (allocator: mem.Allocator) {
//     allocator.procedure = FreeListAllocatorProc
//     allocator.data = list
//     return
// }

// FreeListAllocatorProc :: proc(allocatorData: rawptr, mode: mem.Allocator_Mode, 
//         size, alignment: int, 
//         old_memory: rawptr, old_size: int, 
//         location := #caller_location) -> ([]byte, mem.Allocator_Error)
// {
//     list := cast(^FreeList)allocatorData
//     switch mode {
//         case .Alloc, .Alloc_Non_Zeroed: {
//             memory := FreeListAlloc(list, uint(size), uint(alignment))
//             if mode == .Alloc {
//                 mem.zero(rawptr(memory), size)
//             }

//             offset := memory - uintptr(raw_data(list.data))
//             // fmt.println("Allocating", size, "bytes at", rawptr(offset), "from:", location)
//             // fmt.println("Used memory:", list.used, "Free Memory:", uint(len(list.data)) - list.used)
//             return ([^]byte)(memory)[:size], .None
//         }

//         case .Free: {
//             // fmt.println("Freeing", size, "bytes at", uintptr(old_memory) - uintptr(raw_data(list.data)))
//             FreeListFree(list, old_memory)
//             // fmt.println("Used memory:", list.used, "Free Memory:", uint(len(list.data)) - list.used)

//             return nil, .None
//         }

//         case .Free_All: {
//             FreeListFreeAll(list)
//             return nil, .None
//         }

//         case .Resize, .Resize_Non_Zeroed: {
//             dest := cast(rawptr) FreeListAlloc(list, uint(size), uint(alignment))
//             mem.zero(dest, size)
            
//             mem.copy(dest, old_memory, old_size)

//             FreeListFree(list, old_memory)

//             // fmt.println("Resizing. Removed", old_size, "bytes at", old_memory, ". Allocating", size, "at", dest)
//             return ([^]byte)(dest)[:size], .None
//         }

//         case .Query_Features: {
//             set := (^mem.Allocator_Mode_Set)(old_memory)
//             if set != nil {
//                 set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Free_All, .Query_Features}
//             }
//             return nil, .None
//         }

//         case .Query_Info: {
//             return nil, .Mode_Not_Implemented
//         }
//     }

//     return nil, nil
// }


PAGE_SIZE :: 64 * 1024

// Adapted from https://www.gingerbill.org/article/2021/11/30/memory-allocation-strategies-005/

Free_List_Alloc_Header :: struct {
    block_size: int,
    padding: int,
}

Free_List_Node :: struct {
    next: ^Free_List_Node,
    block_size: int,
}

Placement_Policy :: enum {
    Find_First,
    Find_Best,
}

Free_List :: struct {
    data: []byte,
    used: int,
    head: ^Free_List_Node,
    policy: Placement_Policy,
}

free_list_node_insert :: proc(fl: ^Free_List, prev_node, new_node: ^Free_List_Node) {
    if prev_node == nil {
        if fl.head != nil {
            new_node.next = fl.head
        } else {
            fl.head = new_node
        }
    } else {
        if prev_node.next == nil {
            prev_node.next = new_node
            new_node.next = nil
        } else {
            new_node.next = prev_node.next
            prev_node.next = new_node
        }
    }
}

free_list_node_remove :: proc(fl: ^Free_List, prev_node, del_node: ^Free_List_Node) {
    if prev_node == nil {
        fl.head = del_node.next
    } else {
        prev_node.next = del_node.next
    }
}

calc_padding_with_header :: proc(ptr: uintptr, alignment, header_size: int) -> (padding: int) {
    p, a, modulo, needed_space, pad: uintptr
    p = ptr
    a = cast(uintptr)alignment
    modulo = p & (a - 1)
    if modulo != 0 {
        pad = a - modulo
    }

    needed_space = cast(uintptr)header_size
    if pad < needed_space {
        needed_space -= pad
        if (needed_space & (a - 1)) != 0 {
            pad += a * (1 + needed_space / a)
        } else {
            pad += a * (needed_space / a)
        }
    }

    return cast(int)pad
}

free_list_init :: proc "contextless" (fl: ^Free_List, data: []byte) {
    fl.policy = .Find_First
    //TODO(dragos): do some page alloc in here
    fl.data = data
    free_list_free_all(fl)
}

free_list_free_all :: proc "contextless" (fl: ^Free_List) {
    fl.used = 0
    first_node := cast(^Free_List_Node)raw_data(fl.data)
    first_node.block_size = len(fl.data)
    first_node.next = nil
    fl.head = first_node
}

free_list_find_first :: proc(fl: ^Free_List, size, alignment: int) -> (node: ^Free_List_Node, padding: int, prev_node: ^Free_List_Node) {
    node = fl.head
    for node != nil {
        padding = calc_padding_with_header(cast(uintptr)node, alignment, size_of(Free_List_Alloc_Header))
        required_space := size + padding
        //fmt.printf("pad, align, size: %v %v %v\n", padding, alignment, size)
        //fmt.printf("block_size, required_space: %v %v %v\n", node.block_size, required_space)
        if node.block_size >= required_space do break
        prev_node = node
        node = node.next
    }
    return node, padding, prev_node
}

// Note(Dragos): There is a bug in this one
free_list_find_best :: proc(fl: ^Free_List, size, alignment: int) -> (best_node: ^Free_List_Node, padding: int, prev_node: ^Free_List_Node) {
    smallest_diff := ~uint(0)
    node := fl.head

    for node != nil {
        padding = calc_padding_with_header(cast(uintptr)node, alignment, size_of(Free_List_Alloc_Header))
        //fmt.printf("pad, align, size: %v %v %v\n", padding, alignment, size)
        required_space := size + padding
        //fmt.printf("block_size, required_space, smallest_diff: %v %v\n", node.block_size, required_space, smallest_diff)
        if node.block_size >= required_space && uint(node.block_size - required_space) < smallest_diff {
            best_node = node
            smallest_diff = uint(node.block_size - required_space)
        }
        prev_node = node
        node = node.next
    }

    return best_node, padding, prev_node
}

free_list_find :: proc(fl: ^Free_List, size, alignment: int) -> (best_node: ^Free_List_Node, padding: int, prev_node: ^Free_List_Node) {
    if fl.policy == .Find_Best do return free_list_find_best(fl, size, alignment)
    else do return free_list_find_first(fl, size, alignment)
}


free_list_alloc :: proc(fl: ^Free_List, size, alignment: int) -> (data: []byte, err: mem.Allocator_Error) {
    size := size
    alignment := alignment

    if size < size_of(Free_List_Node) do size = size_of(Free_List_Node)
    if alignment < 8 do alignment = 8

    node, padding, prev_node := free_list_find(fl, size, alignment)
    if node == nil {
        fmt.println("Out of memory. We shouldn't be here.")
        return nil, .Out_Of_Memory
    }

    alignment_padding := padding - size_of(Free_List_Alloc_Header)
    required_space := size + padding
    remaining := node.block_size - required_space
    //fmt.printf("PRE Head, node, prev_node: %v %v %v\n", fl.head, node, prev_node)
    if remaining > 0 {
        new_node := cast(^Free_List_Node)(uintptr(node) + uintptr(required_space))
        new_node.block_size = remaining
        free_list_node_insert(fl, node, new_node)
    }
    free_list_node_remove(fl, prev_node, node)
    //fmt.printf("POST Head, node, prev_node: %v %v %v\n", fl.head, node, prev_node)
    header_ptr := cast(^Free_List_Alloc_Header)(uintptr(node) + uintptr(alignment_padding))
    header_ptr.block_size = required_space
    header_ptr.padding = alignment_padding
    
    fl.used += required_space

    ptr := ([^]byte)(uintptr(header_ptr) + size_of(Free_List_Alloc_Header))
    //fmt.printf("PTR: %v\n", uintptr(ptr))
    return slice.from_ptr(ptr, required_space), .None
}

free_list_free :: proc(fl: ^Free_List, ptr: rawptr) {
    if ptr == nil do return
    header := cast(^Free_List_Alloc_Header)(uintptr(ptr) - size_of(Free_List_Alloc_Header))
    free_node := cast(^Free_List_Node)header
    free_node.block_size = header.block_size + header.padding
    free_node.next = nil
    
    node := fl.head
    prev_node: ^Free_List_Node
    for node != nil {
        if uintptr(ptr) < uintptr(node) {
            free_list_node_insert(fl, prev_node, free_node)
            break
        }
        prev_node = node
        node = node.next
    }
    fl.used -= free_node.block_size
    free_list_merge_nodes(fl, prev_node, free_node)
}

free_list_merge_nodes :: proc(fl: ^Free_List, prev_node, free_node: ^Free_List_Node) {
    if prev_node == nil do return

    if free_node.next != nil && rawptr(uintptr(free_node) + uintptr(free_node.block_size)) == free_node.next {
        free_node.block_size += free_node.next.block_size
        free_list_node_remove(fl, free_node, free_node.next)
    }

    if prev_node.next != nil && rawptr(uintptr(prev_node) + uintptr(prev_node.block_size)) == free_node {
        prev_node.block_size += free_node.block_size
        free_list_node_remove(fl, prev_node, free_node)
    }
}

free_list_allocator :: proc "contextless" (fl: ^Free_List) -> (allocator: mem.Allocator) {
    allocator.procedure = free_list_allocator_proc
    allocator.data = fl
    return allocator
}

free_list_allocator_proc :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode, 
        size, alignment: int, 
        old_memory: rawptr, old_size: int, 
        location := #caller_location) -> ([]byte, mem.Allocator_Error) {
    fl := cast(^Free_List)allocator_data
    switch mode {
        case .Alloc: {
            return free_list_alloc(fl, size, alignment)
        }

        case .Alloc_Non_Zeroed: {
            return free_list_alloc(fl, size, alignment)
        }

        case .Free: {
            free_list_free(fl, old_memory)
            return nil, .None
        }

        case .Free_All: {
            free_list_free_all(fl)
            return nil, .None
        }

        case .Resize, .Resize_Non_Zeroed: {
            // dest, error := free_list_alloc(fl, size, alignment)

            // mem.zero(raw_data(dest), size)
            // mem.copy(raw_data(dest), old_memory, old_size)

            // free_list_free(fl, old_memory)

            // fmt.println("Resizing. Removed", old_size, "bytes at", old_memory, ". Allocating", size, "at", dest)
            // return dest, error
            // return nil, .Mode_Not_Implemented
            return mem.default_resize_bytes_align(mem.byte_slice(old_memory, old_size), size, alignment, free_list_allocator(fl))

        }

        case .Query_Features: {
            set := (^mem.Allocator_Mode_Set)(old_memory)
            if set != nil {
                set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Free_All, .Query_Features}
            }
            return nil, .None
        }

        case .Query_Info: {
            return nil, .Mode_Not_Implemented
        }
    }

    return nil, nil
}