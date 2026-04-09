const std = @import("std");
const core = @import("core");

const types = core.types;

const Phys = types.Phys;

const PAGE_SIZE: u64 = types.PAGE_SIZE;
const BITS_PER_WORD = @bitSizeOf(u64);


pub const Bitmap = struct {
    words: [*]u64,
    len: usize,

    // Example: 256 pages -> 4 words (4 × 64 bits = 256 bits)
    //
    // words[0]: bits 0..63 -> pages 0-63
    // words[1]: bits 0..63 -> pages 64-127
    // words[2]: bits 0..63 -> pages 128-191
    // words[3]: bits 0..63 -> pages 192-255

    const Self = @This();

    /// Allocates a bitmap with `max_pages` bits, starting at `phys`.
    pub fn init(phys: Phys, max_pages: usize) Self {
        const len = wordsNeeded(max_pages);
        const words: [*]u64 = phys.toPtr([*]u64);

        for (0..len) |i| {
            words[i] = std.math.maxInt(u64);
        }

        return .{ .words = words, .len = len };
    }

    pub fn set(self: *Self, page: u32) void {
        const word = page / BITS_PER_WORD;
        const bit: u6 = @intCast(page % BITS_PER_WORD); // u6 2^6 = 64 bits

        // Shift one by "bit" positions
        //   bit 3 -> 0b0000..00001000
        const mask: u64 = @as(u64, 1) << bit;
        self.words[word] = self.words[word] | mask;
    }

    pub fn clear(self: *Self, page: u32) void {
        const word = page / BITS_PER_WORD;
        const bit: u6 = @intCast(page % BITS_PER_WORD);

        const mask: u64 = @as(u64, 1) << bit;

        // Flip all bits, the mask now has 0 where the target bit is.
        const inverted: u64 = ~mask;
        self.words[word] = self.words[word] & inverted;
    }

    pub fn get(self: *Self, page: u32) bool {
         const word = page / BITS_PER_WORD;
         const bit: u6 = @intCast(page % BITS_PER_WORD);

         const mask: u64 = @as(u64, 1) << bit;
         return (self.words[word] & mask) != 0;
    }

    pub fn clearRange(self: *Self, start: usize, count: usize) void {
        for (0..count) |i| {
            self.clear(@intCast(start+i));
        }
    }

    pub fn bytesNeeded(max_pages: usize) usize {
        return wordsNeeded(max_pages) * @sizeOf(u64);
    }

    pub fn pagesNeeded(max_pages: usize) usize {
        return (bytesNeeded(max_pages) + PAGE_SIZE - 1) / PAGE_SIZE;
    }

    fn wordsNeeded(max_pages: usize) usize {
        return (max_pages + BITS_PER_WORD - 1) / BITS_PER_WORD;
    }
};
