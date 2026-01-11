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
