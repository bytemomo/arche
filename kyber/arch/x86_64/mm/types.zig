const common_types = @import("core").types;

pub const Phys = common_types.Phys;
pub const Size = common_types.Size;
pub const PageCount = common_types.PageCount;
pub const Pixels = common_types.Pixels;
pub const BytesPerRow = common_types.BytesPerRow;
pub const BitsPerPixel = common_types.BitsPerPixel;

pub const Virt = extern struct {
    value: u64,

    pub fn from(addr: u64) Virt {
        return .{ .value = addr };
    }

    pub fn raw(self: Virt) u64 {
        return self.value;
    }

    pub fn add(self: Virt, offset: u64) Virt {
        return .{ .value = self.value + offset };
    }

    pub fn sub(self: Virt, offset: u64) Virt {
        return .{ .value = self.value - offset };
    }

    pub fn alignDown(self: Virt, alignment: u64) Virt {
        return .{ .value = self.value & ~(alignment - 1) };
    }

    pub fn alignUp(self: Virt, alignment: u64) Virt {
        return .{ .value = (self.value + alignment - 1) & ~(alignment - 1) };
    }

    pub fn isAligned(self: Virt, alignment: u64) bool {
        return (self.value & (alignment - 1)) == 0;
    }

    pub fn fromPtr(ptr: anytype) Virt {
        return .{ .value = @intFromPtr(ptr) };
    }

    pub fn toPtr(self: Virt, comptime T: type) T {
        return @ptrFromInt(self.value);
    }

    // x86_64-specific: 4-level paging index extraction

    /// Extract PML4 index (bits 39-47).
    pub fn pml4Index(self: Virt) u9 {
        return @truncate((self.value >> 39) & 0x1FF);
    }

    /// Extract PDPT index (bits 30-38).
    pub fn pdptIndex(self: Virt) u9 {
        return @truncate((self.value >> 30) & 0x1FF);
    }

    /// Extract PD index (bits 21-29).
    pub fn pdIndex(self: Virt) u9 {
        return @truncate((self.value >> 21) & 0x1FF);
    }

    /// Extract PT index (bits 12-20).
    pub fn ptIndex(self: Virt) u9 {
        return @truncate((self.value >> 12) & 0x1FF);
    }

    /// Extract page offset (bits 0-11).
    pub fn pageOffset(self: Virt) u12 {
        return @truncate(self.value & 0xFFF);
    }
};

const testing = @import("std").testing;

test "Virt paging indices for address zero" {
    const v = Virt.from(0);
    try testing.expectEqual(@as(u9, 0), v.pml4Index());
    try testing.expectEqual(@as(u9, 0), v.pdptIndex());
    try testing.expectEqual(@as(u9, 0), v.pdIndex());
    try testing.expectEqual(@as(u9, 0), v.ptIndex());
    try testing.expectEqual(@as(u12, 0), v.pageOffset());
}

test "Virt paging indices for known address" {
    // Construct: pml4=1, pdpt=2, pd=3, pt=4, offset=0x567
    const addr = (@as(u64, 1) << 39) |
        (@as(u64, 2) << 30) |
        (@as(u64, 3) << 21) |
        (@as(u64, 4) << 12) |
        0x567;
    const v = Virt.from(addr);
    try testing.expectEqual(@as(u9, 1), v.pml4Index());
    try testing.expectEqual(@as(u9, 2), v.pdptIndex());
    try testing.expectEqual(@as(u9, 3), v.pdIndex());
    try testing.expectEqual(@as(u9, 4), v.ptIndex());
    try testing.expectEqual(@as(u12, 0x567), v.pageOffset());
}

test "Virt paging indices at max values" {
    // All index fields set to 0x1FF (511), offset 0xFFF
    const addr = (@as(u64, 0x1FF) << 39) |
        (@as(u64, 0x1FF) << 30) |
        (@as(u64, 0x1FF) << 21) |
        (@as(u64, 0x1FF) << 12) |
        0xFFF;
    const v = Virt.from(addr);
    try testing.expectEqual(@as(u9, 0x1FF), v.pml4Index());
    try testing.expectEqual(@as(u9, 0x1FF), v.pdptIndex());
    try testing.expectEqual(@as(u9, 0x1FF), v.pdIndex());
    try testing.expectEqual(@as(u9, 0x1FF), v.ptIndex());
    try testing.expectEqual(@as(u12, 0xFFF), v.pageOffset());
}
