const std = @import("std");
const core = @import("core");
const log = core.log;

const slab_cache = @import("slab_cache.zig");

/// Per-CPU magazine - a small fixed-size array of pre-allocated
/// object pointers. Most alloc/free just push/pop from this array.
pub fn Magazine(comptime T: type) type {
    return struct {
        rounds: [CAPACITY]?*T,
        count: u8,

        const Self = @This();
        pub const CAPACITY: u8 = 15;

        pub fn empty() Self {
            return .{
                .rounds = [_]?*T{null} ** CAPACITY,
                .count = 0,
            };
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.count == 0;
        }

        pub fn isFull(self: *const Self) bool {
            return self.count == CAPACITY;
        }

        pub fn push(self: *Self, ptr: *T) void {
            self.rounds[self.count] = ptr;
            self.count += 1;
        }

        pub fn pop(self: *Self) ?*T {
            if (self.count == 0) return null;
            self.count -= 1;
            const ptr = self.rounds[self.count];
            self.rounds[self.count] = null;
            return ptr;
        }
    };
}

/// Per-CPU allocator wrapping a SlabCache(T) with two magazines.
///
///   alloc():
///     loaded not empty? -> pop from loaded     (fast, no lock)
///     reserve not empty? -> swap, then pop     (fast, no lock)
///     both empty? -> refill from slab cache    (slow path)
///
///   free(ptr):
///     loaded not full? -> push to loaded       (fast, no lock)
///     reserve not full? -> swap, then push     (fast, no lock)
///     both full? -> flush loaded to slab cache (slow path)
///
pub fn MagazineAllocator(comptime T: type) type {
    const Cache = slab_cache.SlabCache(T);
    const Mag = Magazine(T);

    return struct {
        loaded: Mag,
        reserve: Mag,
        cache: *Cache,

        const Self = @This();

        pub fn init(cache: *Cache) Self {
            return .{
                .loaded = Mag.empty(),
                .reserve = Mag.empty(),
                .cache = cache,
            };
        }

        pub fn alloc(self: *Self) ?*T {
            if (self.loaded.pop()) |ptr| return ptr;

            if (!self.reserve.isEmpty()) {
                self.swap();
                return self.loaded.pop();
            }

            self.refill();
            return self.loaded.pop();
        }

        pub fn free(self: *Self, ptr: *T) void {
            if (!self.loaded.isFull()) {
                self.loaded.push(ptr);
                return;
            }

            if (!self.reserve.isFull()) {
                self.swap();
                self.loaded.push(ptr);
                return;
            }

            self.flush();
            self.loaded.push(ptr);
        }

        fn swap(self: *Self) void {
            const tmp = self.loaded;
            self.loaded = self.reserve;
            self.reserve = tmp;
        }

        fn refill(self: *Self) void {
            while (!self.loaded.isFull()) {
                const ptr = self.cache.alloc() orelse break;
                self.loaded.push(ptr);
            }
        }

        fn flush(self: *Self) void {
            while (self.loaded.pop()) |ptr| {
                self.cache.free(ptr);
            }
        }
    };
}
