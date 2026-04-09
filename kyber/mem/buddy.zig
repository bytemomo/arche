const std = @import("std");
const core = @import("core");

const log = core.log;
const types = core.types;
const boot_info = core.boot_info;

const Bitmap = @import("utils/bitmap.zig").Bitmap;
const FreeList = @import("utils/freelist.zig").FreeList;

const Phys = types.Phys;
const Size = types.Size;
const PAGE_SIZE: u64 = types.PAGE_SIZE;

pub const MAX_ORDER: u5 = 10;
const ORDER_COUNT = MAX_ORDER + 1;

/// Pages below this are reserved.
const RESERVED_PAGES: usize = 0x100;

pub const BuddyAllocator = struct {
    bitmap: Bitmap,
    free_lists: [ORDER_COUNT]FreeList,
    max_pages: usize,
    total_pages: usize,
    free_pages: usize,

    const Self = @This();

    /// Walk the UEFI memory map, steal a region for the bitmap,
    /// then populate free lists from all usable regions.
    pub fn initInPlace(
        self: *Self,
        memory_map: boot_info.MemoryMap,
    ) void {
        const highest = findHighestAddress(memory_map);
        const max_pages: usize = @intCast(highest / PAGE_SIZE);
        const bitmap_phys = stealBitmapMemory(
            memory_map,
            Bitmap.bytesNeeded(max_pages),
        );

        self.* = .{
            .bitmap = Bitmap.init(bitmap_phys, max_pages),
            .free_lists = [_]FreeList{
                FreeList.empty(),
            } ** ORDER_COUNT,
            .max_pages = max_pages,
            .total_pages = 0,
            .free_pages = 0,
        };

        const bitmap_start = bitmap_phys.raw() / PAGE_SIZE;
        const bitmap_end = bitmap_start +
            Bitmap.pagesNeeded(max_pages);

        for (memory_map.slice()) |region| {
            if (region.mem_type != .usable) continue;
            self.addRegion(region, bitmap_start, bitmap_end);
        }

        const free_mib = (self.free_pages * 4096) >> 20;
        const total_mib = (self.total_pages * 4096) >> 20;

        log.info(@src(), "buddy ready", .{});
        log.writeSerial("  free=");
        log.writeSerialDec(self.free_pages);
        log.writeSerial(" pages (");
        log.writeSerialDec(free_mib);
        log.writeSerial(" MiB) / total=");
        log.writeSerialDec(self.total_pages);
        log.writeSerial(" pages (");
        log.writeSerialDec(total_mib);
        log.writeSerial(" MiB)\n");
    }

    /// Allocate `count` contiguous physical pages.
    /// Rounds up to the nearest power-of-2 block.
    pub fn allocPages(self: *Self, count: usize) ?Phys {
        const order = orderForPages(count);
        const page = self.allocOrder(order) orelse return null;
        return Phys.from(@as(u64, page) * PAGE_SIZE);
    }

    /// Free `count` contiguous pages starting at `addr`.
    pub fn freePages(self: *Self, addr: Phys, count: usize) void {
        const order = orderForPages(count);
        const page: u32 = @intCast(addr.raw() / PAGE_SIZE);
        self.freeOrder(page, order);
    }

    /// Return a std.mem.Allocator backed by this buddy.
    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    /// Find a free block of the requested order.
    /// If none exists, find a larger block and split it down.
    ///
    /// Example: allocOrder(0) wants 1 page, smallest free is order 3.
    ///   order 3 (8 pages): pop block at page 0
    ///   split -> order 2: push buddy (page 4) onto free list
    ///   split -> order 1: push buddy (page 2) onto free list
    ///   split -> order 0: push buddy (page 1) onto free list
    ///   return page 0
    fn allocOrder(self: *Self, order: u5) ?u32 {
        // Walk up to find a non-empty free list.
        var current: u5 = order;
        while (current <= MAX_ORDER) : (current += 1) {
            if (!self.free_lists[current].isEmpty()) break;
        } else {
            return null;
        }

        // Pop the block and mark it as used.
        const page = self.free_lists[current].pop().?;
        self.bitmap.set(page);

        // Split down: each iteration halves the block, putting
        // the upper buddy on the free list and keeping the lower.
        while (current > order) {
            current -= 1;
            const buddy = page +
                (@as(u32, 1) << @intCast(current));
            self.bitmap.clear(buddy);
            self.free_lists[current].push(buddy);
        }

        self.free_pages -= pagesForOrder(order);
        return page;
    }

    /// Free a block and merge with its buddy recursively.
    ///
    /// The buddy of page P at order O is P XOR (1 << O).
    /// If the buddy is also free (bitmap bit = 0), remove it
    /// from its free list, merge into a block one order larger,
    /// and repeat until the buddy is in use or we hit MAX_ORDER.
    ///
    /// Example: freeOrder(page 1, order 0)
    ///   buddy of page 1 at order 0 = 1 XOR 1 = page 0
    ///   page 0 is free -> merge into page 0, order 1
    ///   buddy of page 0 at order 1 = 0 XOR 2 = page 2
    ///   page 2 is free -> merge into page 0, order 2
    ///   buddy of page 0 at order 2 = 0 XOR 4 = page 4
    ///   page 4 is in use -> stop, push page 0 onto order-2 list
    fn freeOrder(
        self: *Self,
        page: u32,
        initial_order: u5,
    ) void {
        var current_page = page;
        var order = initial_order;

        self.free_pages += pagesForOrder(order);

        while (order < MAX_ORDER) {
            const buddy = buddyOf(current_page, order);
            if (buddy >= self.max_pages) break;
            if (self.bitmap.get(buddy)) break;

            self.free_lists[order].remove(buddy);
            if (buddy < current_page) current_page = buddy;
            order += 1;
        }

        self.bitmap.clear(current_page);
        self.free_lists[order].push(current_page);
    }

    /// Add a usable memory region to the free lists, skipping
    /// reserved pages and the bitmap's own pages.
    fn addRegion(
        self: *Self,
        region: boot_info.MemoryRegion,
        bitmap_start: usize,
        bitmap_end: usize,
    ) void {
        var page = region.phys_start.raw() / PAGE_SIZE;
        const region_end = page + @as(
            usize,
            @intCast(region.page_count.raw()),
        );

        if (page < RESERVED_PAGES) page = RESERVED_PAGES;
        if (region_end <= page) return;
        if (region_end > self.max_pages) return;

        self.total_pages += @intCast(region.page_count.raw());

        while (page < region_end) {
            // Skip pages occupied by the bitmap itself.
            if (page >= bitmap_start and page < bitmap_end) {
                page += 1;
                continue;
            }

            // Don't form a block that straddles the bitmap.
            var limit = region_end;
            if (bitmap_start > page and bitmap_start < limit) {
                limit = bitmap_start;
            }

            const order = maxOrderForPage(page, limit);
            const count = pagesForOrder(order);

            self.bitmap.clearRange(page, count);
            self.free_lists[order].push(@intCast(page));
            self.free_pages += count;

            page += count;
        }
    }

    // Allocator
    const vtable = std.mem.Allocator.VTable{
        .alloc = vtableAlloc,
        .resize = vtableResize,
        .free = vtableFree,
    };

    fn vtableAlloc(ctx: *anyopaque, len: usize, _: std.mem.Alignment, _: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const count = Size.from(len).toPageCount().raw();
        const addr = self.allocPages(@intCast(count)) orelse return null;
        return addr.toPtr([*]u8);
    }

    fn vtableResize(
        _: *anyopaque,
        _: []u8,
        _: std.mem.Alignment,
        _: usize,
        _: usize,
    ) bool {
        return false;
    }

    fn vtableFree(
        ctx: *anyopaque,
        buf: []u8,
        _: std.mem.Alignment,
        _: usize,
    ) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const count: usize = @intCast(
            Size.from(buf.len).toPageCount().raw(),
        );
        self.freePages(Phys.fromPtr(buf.ptr), count);
    }
};

fn findHighestAddress(map: boot_info.MemoryMap) u64 {
    var highest: u64 = 0;
    for (map.slice()) |region| {
        const end = region.physEnd().raw();
        if (end > highest) highest = end;
    }
    return highest;
}

/// Find the first usable region large enough to hold the bitmap
/// and return its physical start address.
fn stealBitmapMemory(
    map: boot_info.MemoryMap,
    bytes: usize,
) Phys {
    const pages_needed = (bytes + PAGE_SIZE - 1) / PAGE_SIZE;
    for (map.slice()) |region| {
        if (region.mem_type != .usable) continue;
        if (region.page_count.raw() >= pages_needed) {
            return region.phys_start;
        }
    }
    @panic("buddy: no region large enough for bitmap");
}

/// Buddy address: XOR the page number with the block size.
fn buddyOf(page: u32, order: u5) u32 {
    return page ^ (@as(u32, 1) << @intCast(order));
}

/// Smallest order where 2^order >= count.
fn orderForPages(count: usize) u5 {
    if (count <= 1) return 0;
    const bits = @bitSizeOf(usize) - @clz(count - 1);
    return @intCast(bits);
}

/// Number of pages in a block of given order. 2^order.
fn pagesForOrder(order: u5) usize {
    return @as(usize, 1) << @intCast(order);
}

/// Largest power-of-2 block starting at `page` that is
/// naturally aligned and fits before `end`.
fn maxOrderForPage(page: usize, end: usize) u5 {
    var order: u5 = 0;
    while (order < MAX_ORDER) {
        const next_order = order + 1;
        const next_size = pagesForOrder(next_order);
        if (page % next_size != 0) break;
        if (page + next_size > end) break;
        order = next_order;
    }
    return order;
}
