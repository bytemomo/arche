const std = @import("std");
const core = @import("core");
const boot_info = core.boot_info;
const types = core.types;

const Phys = types.Phys;
const Size = types.Size;
const PageCount = types.PageCount;

const Self = @This();

const BITS_PER_WORD = @bitSizeOf(u64);
const ALL_USED: u64 = std.math.maxInt(u64);

/// Maximum physical pages tracked (4 GiB).
const MAX_PAGES: usize = Size.gib(4).toPageCount().raw();
const BITMAP_LEN = MAX_PAGES / BITS_PER_WORD;

/// Pages below this are reserved (null page, real-mode IVT, BDA).
const RESERVED_PAGES: usize = 0x100; // first 1 MiB

bitmap: [BITMAP_LEN]u64,
total_pages: usize,
free_pages: usize,

pub fn init(memory_map: boot_info.MemoryMap) Self {
    var self = Self{
        .bitmap = [_]u64{ALL_USED} ** BITMAP_LEN,
        .total_pages = 0,
        .free_pages = 0,
    };
    self.populateFromMap(memory_map);
    return self;
}

/// Initialize in place, avoiding a 128 KiB stack copy.
pub fn initInPlace(self: *Self, memory_map: boot_info.MemoryMap) void {
    self.bitmap = [_]u64{ALL_USED} ** BITMAP_LEN;
    self.total_pages = 0;
    self.free_pages = 0;
    self.populateFromMap(memory_map);
}

fn populateFromMap(self: *Self, memory_map: boot_info.MemoryMap) void {
    for (memory_map.slice()) |region| {
        if (region.mem_type != .usable) continue;

        const start_page = region.phys_start.raw() / types.PAGE_SIZE;
        const count: usize = @intCast(region.page_count.raw());

        for (0..count) |i| {
            const page = start_page + i;
            if (page >= RESERVED_PAGES and page < MAX_PAGES) {
                self.markFree(page);
                self.free_pages += 1;
            }
        }
        self.total_pages += count;
    }
}

pub fn allocator(self: *Self) std.mem.Allocator {
    return .{
        .ptr = self,
        .vtable = &vtable,
    };
}

pub fn allocPages(self: *Self, count: usize) ?Phys {
    const start = self.findFreeRun(count) orelse return null;

    for (0..count) |i| {
        self.markUsed(start + i);
    }
    self.free_pages -= count;

    return Phys.from(start * types.PAGE_SIZE);
}

pub fn freePages(self: *Self, addr: Phys, count: usize) void {
    const start: usize = @intCast(addr.raw() / types.PAGE_SIZE);

    for (0..count) |i| {
        self.markFree(start + i);
    }
    self.free_pages += count;
}


fn isUsed(self: *const Self, page: usize) bool {
    const word = page / BITS_PER_WORD;
    const bit: u6 = @intCast(page % BITS_PER_WORD);
    return (self.bitmap[word] & (@as(u64, 1) << bit)) != 0;
}

fn markUsed(self: *Self, page: usize) void {
    const word = page / BITS_PER_WORD;
    const bit: u6 = @intCast(page % BITS_PER_WORD);
    self.bitmap[word] |= @as(u64, 1) << bit;
}

fn markFree(self: *Self, page: usize) void {
    const word = page / BITS_PER_WORD;
    const bit: u6 = @intCast(page % BITS_PER_WORD);
    self.bitmap[word] &= ~(@as(u64, 1) << bit);
}

fn findFreeRun(self: *const Self, count: usize) ?usize {
    var run_start: usize = 0;
    var run_len: usize = 0;

    for (0..MAX_PAGES) |page| {
        if (self.isUsed(page)) {
            run_start = page + 1;
            run_len = 0;
        } else {
            run_len += 1;
            if (run_len == count) return run_start;
        }
    }
    return null;
}


const vtable = std.mem.Allocator.VTable{
    .alloc = _alloc,
    .resize = _resize,
    .free = _free,
};

fn _alloc(
    ctx: *anyopaque,
    len: usize,
    _: std.mem.Alignment,
    _: usize,
) ?[*]u8 {
    const self: *Self = @ptrCast(@alignCast(ctx));
    const page_count = Size.from(len).toPageCount().raw();
    const addr = self.allocPages(@intCast(page_count)) orelse return null;
    return addr.toPtr([*]u8);
}

fn _resize(
    _: *anyopaque,
    _: []u8,
    _: std.mem.Alignment,
    _: usize,
    _: usize,
) bool {
    return false;
}

fn _free(
    ctx: *anyopaque,
    buf: []u8,
    _: std.mem.Alignment,
    _: usize,
) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    const page_count: usize = @intCast(Size.from(buf.len).toPageCount().raw());
    self.freePages(Phys.fromPtr(buf.ptr), page_count);
}
