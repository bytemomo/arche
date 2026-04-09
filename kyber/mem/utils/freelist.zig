const std = @import("std");

const types = @import("core").types;

const PAGE_SIZE: u64 = types.PAGE_SIZE;

/// Doubly-linked free list using intrusive nodes stored inside
/// free pages themselves. Tracks page numbers (u32), not addresses.
/// Doubly-linked so that remove() during buddy merge is O(1).
pub const FreeList = struct {
    /// Page number of the first free block, or null if empty.
    head: ?u32,

    const Self = @This();
    const SENTINEL: u32 = std.math.maxInt(u32); // 0xFFFFFFFF = "no link"

    /// Written directly into a free page's physical memory.
    /// Free pages aren't used for anything, so we store the list
    /// pointers inside them. Once allocated, the caller overwrites
    /// this with whatever they want.
    const Node = extern struct {
        next: u32, // page number of next free block
        prev: u32, // page number of previous free block
    };

    pub fn empty() Self {
        return .{ .head = null };
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.head == null;
    }

    /// Insert at front.
    /// Before: head -> [A] <-> [B] <-> [C]
    /// push(X)
    /// After:  head -> [X] <-> [A] <-> [B] <-> [C]
    pub fn push(self: *Self, page: u32) void {
        const node = nodePtr(page);
        node.prev = SENTINEL;

        if (self.head) |curr_head| {
            node.next = curr_head;
            nodePtr(curr_head).prev = page;
        } else {
            node.next = SENTINEL;
        }

        self.head = page;
    }

    /// Remove and return the head.
    /// Before: head -> [A] <-> [B] <-> [C]
    /// pop() returns A
    /// After:  head -> [B] <-> [C]
    pub fn pop(self: *Self) ?u32 {
        const page = self.head orelse return null;
        const node = nodePtr(page);

        if (node.next != SENTINEL) {
            nodePtr(node.next).prev = SENTINEL;
            self.head = node.next;
        } else {
            self.head = null;
        }

        return page;
    }

    /// Remove a specific page from anywhere in the list.
    /// Used during buddy merge to pull the buddy out of its
    /// order's free list in O(1).
    /// Before: head -> [A] <-> [B] <-> [C]
    /// remove(B)
    /// After:  head -> [A] <-> [C]
    pub fn remove(self: *Self, page: u32) void {
        const node = nodePtr(page);

        if (node.prev != SENTINEL) {
            nodePtr(node.prev).next = node.next;
        } else {
            self.head = if (node.next != SENTINEL)
                node.next
            else
                null;
        }

        if (node.next != SENTINEL) {
            nodePtr(node.next).prev = node.prev;
        }
    }

    /// Convert page number to pointer to the Node stored at
    /// that page's physical address.
    /// page 5 -> address 0x5000 -> cast to *Node
    /// Works because identity map is active (virtual == physical).
    fn nodePtr(page: u32) *Node {
        return @ptrFromInt(@as(u64, page) * PAGE_SIZE);
    }
};
