pub const PAGE_SIZE: u64 = 4096;

pub const Phys = extern struct {
    value: u64,

    pub fn from(addr: u64) Phys {
        return .{ .value = addr };
    }

    pub fn raw(self: Phys) u64 {
        return self.value;
    }

    pub fn add(self: Phys, offset: u64) Phys {
        return .{ .value = self.value + offset };
    }

    pub fn sub(self: Phys, offset: u64) Phys {
        return .{ .value = self.value - offset };
    }

    pub fn alignDown(self: Phys, alignment: u64) Phys {
        return .{ .value = self.value & ~(alignment - 1) };
    }

    pub fn alignUp(self: Phys, alignment: u64) Phys {
        return .{ .value = (self.value + alignment - 1) & ~(alignment - 1) };
    }

    pub fn isAligned(self: Phys, alignment: u64) bool {
        return (self.value & (alignment - 1)) == 0;
    }

    pub fn fromPtr(ptr: anytype) Phys {
        return .{ .value = @intFromPtr(ptr) };
    }

    pub fn toPtr(self: Phys, comptime T: type) T {
        return @ptrFromInt(self.value);
    }
};

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
};

pub const PageCount = extern struct {
    value: u64,

    pub const ZERO: PageCount = .{ .value = 0 };

    pub fn from(count: u64) PageCount {
        return .{ .value = count };
    }

    pub fn raw(self: PageCount) u64 {
        return self.value;
    }

    pub fn toBytes(self: PageCount) Size {
        return Size.from(self.value * 4096);
    }

    pub fn add(self: PageCount, other: PageCount) PageCount {
        return .{ .value = self.value + other.value };
    }

    pub fn sub(self: PageCount, other: PageCount) PageCount {
        return .{ .value = self.value - other.value };
    }
};

pub const Size = extern struct {
    value: u64,

    pub const ZERO: Size = .{ .value = 0 };

    pub const KiB: u64 = 1024;
    pub const MiB: u64 = 1024 * KiB;
    pub const GiB: u64 = 1024 * MiB;
    pub const TiB: u64 = 1024 * GiB;

    pub fn from(bytes: u64) Size {
        return .{ .value = bytes };
    }

    pub fn raw(self: Size) u64 {
        return self.value;
    }

    pub fn toPageCount(self: Size) PageCount {
        return PageCount.from((self.value + 4095) / 4096);
    }

    pub fn add(self: Size, other: Size) Size {
        return .{ .value = self.value + other.value };
    }

    pub fn sub(self: Size, other: Size) Size {
        return .{ .value = self.value - other.value };
    }

    pub fn alignUp(self: Size, comptime alignment: u64) Size {
        return .{ .value = (self.value + alignment - 1) & ~(alignment - 1) };
    }

    pub fn alignDown(self: Size, comptime alignment: u64) Size {
        return .{ .value = self.value & ~(alignment - 1) };
    }

    pub fn kib(count: u64) Size {
        return .{ .value = count * KiB };
    }

    pub fn mib(count: u64) Size {
        return .{ .value = count * MiB };
    }

    pub fn gib(count: u64) Size {
        return .{ .value = count * GiB };
    }

    pub fn tib(count: u64) Size {
        return .{ .value = count * TiB };
    }
};

pub const Pixels = extern struct {
    value: u32,

    pub fn from(px: u32) Pixels {
        return .{ .value = px };
    }

    pub fn raw(self: Pixels) u32 {
        return self.value;
    }
};

pub const BytesPerRow = extern struct {
    value: u32,

    pub fn from(bytes: u32) BytesPerRow {
        return .{ .value = bytes };
    }

    pub fn raw(self: BytesPerRow) u32 {
        return self.value;
    }
};

pub const BitsPerPixel = extern struct {
    value: u16,

    pub fn from(bpp: u16) BitsPerPixel {
        return .{ .value = bpp };
    }

    pub fn raw(self: BitsPerPixel) u16 {
        return self.value;
    }

    pub fn bytesPerPixel(self: BitsPerPixel) u16 {
        return (self.value + 7) / 8;
    }
};

const testing = @import("std").testing;

test "Phys from/raw roundtrip" {
    const addr = Phys.from(0xDEAD_BEEF);
    try testing.expectEqual(@as(u64, 0xDEAD_BEEF), addr.raw());
}

test "Phys add/sub" {
    const base = Phys.from(0x1000);
    try testing.expectEqual(@as(u64, 0x1100), base.add(0x100).raw());
    try testing.expectEqual(@as(u64, 0x0F00), base.sub(0x100).raw());
}

test "Phys alignDown/alignUp/isAligned" {
    const addr = Phys.from(0x1234);
    try testing.expectEqual(@as(u64, 0x1000), addr.alignDown(0x1000).raw());
    try testing.expectEqual(@as(u64, 0x2000), addr.alignUp(0x1000).raw());
    try testing.expect(!addr.isAligned(0x1000));
    try testing.expect(Phys.from(0x1000).isAligned(0x1000));
}

test "Virt from/raw roundtrip" {
    const addr = Virt.from(0xCAFE_BABE);
    try testing.expectEqual(@as(u64, 0xCAFE_BABE), addr.raw());
}

test "Virt add/sub" {
    const base = Virt.from(0x2000);
    try testing.expectEqual(@as(u64, 0x2200), base.add(0x200).raw());
    try testing.expectEqual(@as(u64, 0x1E00), base.sub(0x200).raw());
}

test "Virt alignDown/alignUp/isAligned" {
    const addr = Virt.from(0x3456);
    try testing.expectEqual(@as(u64, 0x3000), addr.alignDown(0x1000).raw());
    try testing.expectEqual(@as(u64, 0x4000), addr.alignUp(0x1000).raw());
    try testing.expect(!addr.isAligned(0x1000));
    try testing.expect(Virt.from(0x4000).isAligned(0x1000));
}

test "Size from/raw and unit constructors" {
    try testing.expectEqual(@as(u64, 42), Size.from(42).raw());
    try testing.expectEqual(@as(u64, 1024), Size.kib(1).raw());
    try testing.expectEqual(@as(u64, 1024 * 1024), Size.mib(1).raw());
    try testing.expectEqual(@as(u64, 1024 * 1024 * 1024), Size.gib(1).raw());
    try testing.expectEqual(@as(u64, 1024 * 1024 * 1024 * 1024), Size.tib(1).raw());
}

test "Size toPageCount" {
    try testing.expectEqual(@as(u64, 1), Size.from(4096).toPageCount().raw());
    try testing.expectEqual(@as(u64, 1), Size.from(1).toPageCount().raw());
    try testing.expectEqual(@as(u64, 2), Size.from(4097).toPageCount().raw());
    try testing.expectEqual(@as(u64, 0), Size.from(0).toPageCount().raw());
}

test "Size alignUp/alignDown" {
    const s = Size.from(5000);
    try testing.expectEqual(@as(u64, 8192), s.alignUp(4096).raw());
    try testing.expectEqual(@as(u64, 4096), s.alignDown(4096).raw());
}

test "PageCount from/raw and toBytes" {
    const pc = PageCount.from(3);
    try testing.expectEqual(@as(u64, 3), pc.raw());
    try testing.expectEqual(@as(u64, 3 * 4096), pc.toBytes().raw());
}

test "PageCount add/sub" {
    const a = PageCount.from(5);
    const b = PageCount.from(2);
    try testing.expectEqual(@as(u64, 7), a.add(b).raw());
    try testing.expectEqual(@as(u64, 3), a.sub(b).raw());
}

test "BitsPerPixel bytesPerPixel" {
    try testing.expectEqual(@as(u16, 3), BitsPerPixel.from(24).bytesPerPixel());
    try testing.expectEqual(@as(u16, 4), BitsPerPixel.from(32).bytesPerPixel());
    try testing.expectEqual(@as(u16, 1), BitsPerPixel.from(8).bytesPerPixel());
    try testing.expectEqual(@as(u16, 2), BitsPerPixel.from(16).bytesPerPixel());
    try testing.expectEqual(@as(u16, 2), BitsPerPixel.from(15).bytesPerPixel());
}
