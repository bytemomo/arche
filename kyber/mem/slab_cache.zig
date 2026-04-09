const std = @import("std");
const core = @import("core");
const log = core.log;
const types = core.types;

const Phys = types.Phys;
const PAGE_SIZE: usize = @intCast(types.PAGE_SIZE);

const Buddy = @import("buddy.zig");

/// A typed slab cache that allocates fixed-size objects of type T
/// from buddy-provided pages.
pub fn SlabCache(comptime T: type) type {
    return struct {
        buddy: *Buddy.BuddyAllocator,
        slabs: ?*Slab,
        allocated: usize,
        available: usize,

        const Self = @This();
        const SENTINEL: u16 = std.math.maxInt(u16);

        /// Freelist index stored inside each free slot.
        const FreeSlot = struct {
            next: u16,
        };

        const obj_align = @max(@alignOf(T), @alignOf(FreeSlot));
        const obj_size = @max(
            std.mem.alignForward(
                usize,
                @max(@sizeOf(T), 1),
                obj_align,
            ),
            @sizeOf(FreeSlot),
        );

        /// Metadata stored at the end of each slab page.
        ///
        /// Page layout:
        ///   [slot 0][slot 1]...[slot N-1][  Slab metadata  ]
        ///    ^                            ^
        ///    base                         base + N * obj_size
        ///
        const Slab = struct {
            free_head: u16,
            slot_count: u16,
            used_count: u16,
            _pad: u16 = 0,
            next: ?*Slab,
            prev: ?*Slab,
            base: [*]u8,
        };

        const meta_size = std.mem.alignForward(
            usize,
            @sizeOf(Slab),
            obj_align,
        );

        /// Number of objects that fit in one slab page.
        pub const slots_per_slab: u16 = @intCast(
            (PAGE_SIZE - meta_size) / obj_size,
        );

        pub fn init(buddy: *Buddy.BuddyAllocator) Self {
            return .{
                .buddy = buddy,
                .slabs = null,
                .allocated = 0,
                .available = 0,
            };
        }

        /// Allocate one T from the cache.
        pub fn alloc(self: *Self) ?*T {
            const slab = self.findFreeSlab() orelse
                self.growSlab() orelse return null;

            const slot_idx = slab.free_head;
            const ptr = slotPtr(slab, slot_idx);
            const free_slot: *FreeSlot = @ptrCast(
                @alignCast(ptr),
            );

            slab.free_head = free_slot.next;
            slab.used_count += 1;
            self.allocated += 1;
            self.available -= 1;

            return @ptrCast(@alignCast(ptr));
        }

        /// Free one T back to the cache.
        pub fn free(self: *Self, obj: *T) void {
            const ptr: [*]u8 = @ptrCast(obj);
            const addr = @intFromPtr(ptr);
            const page_addr = addr & ~@as(u64, PAGE_SIZE - 1);
            const slab = self.findSlab(page_addr) orelse return;

            const slot_idx = slotIndex(slab, ptr);
            const free_slot: *FreeSlot = @ptrCast(
                @alignCast(ptr),
            );
            free_slot.next = slab.free_head;
            slab.free_head = slot_idx;

            slab.used_count -= 1;
            self.allocated -= 1;
            self.available += 1;

            // Return completely empty slabs to the buddy,
            // but keep at least one slab around.
            if (slab.used_count == 0 and self.slabs != slab) {
                self.removeSlab(slab);
                self.available -= slab.slot_count;
                self.buddy.freePages(Phys.from(page_addr), 1);
            }
        }

        fn growSlab(self: *Self) ?*Slab {
            const phys = self.buddy.allocPages(1) orelse return null;
            const base: [*]u8 = phys.toPtr([*]u8);

            const slab: *Slab = @ptrCast(@alignCast(
                base + @as(usize, slots_per_slab) * obj_size,
            ));

            slab.* = .{
                .free_head = 0,
                .slot_count = slots_per_slab,
                .used_count = 0,
                .next = self.slabs,
                .prev = null,
                .base = base,
            };

            for (0..slots_per_slab) |i| {
                const slot = slotPtr(slab, @intCast(i));
                const fs: *FreeSlot = @ptrCast(
                    @alignCast(slot),
                );
                fs.next = if (i + 1 < slots_per_slab)
                    @intCast(i + 1)
                else
                    SENTINEL;
            }

            if (self.slabs) |old_head| {
                old_head.prev = slab;
            }
            self.slabs = slab;
            self.available += slots_per_slab;

            return slab;
        }

        fn findFreeSlab(self: *Self) ?*Slab {
            var slab = self.slabs;
            while (slab) |s| {
                if (s.free_head != SENTINEL) return s;
                slab = s.next;
            }
            return null;
        }

        fn findSlab(self: *Self, page_addr: u64) ?*Slab {
            var slab = self.slabs;
            while (slab) |s| {
                if (@intFromPtr(s.base) == page_addr) return s;
                slab = s.next;
            }
            return null;
        }

        fn removeSlab(self: *Self, slab: *Slab) void {
            if (slab.prev) |prev| {
                prev.next = slab.next;
            } else {
                self.slabs = slab.next;
            }
            if (slab.next) |next| {
                next.prev = slab.prev;
            }
        }

        fn slotPtr(slab: *Slab, idx: u16) [*]u8 {
            return slab.base + @as(usize, idx) * obj_size;
        }

        fn slotIndex(slab: *Slab, ptr: [*]u8) u16 {
            const offset = @intFromPtr(ptr) - @intFromPtr(slab.base);
            return @intCast(offset / obj_size);
        }
    };
}
