const types = @import("types.zig");

pub const Phys = types.Phys;
pub const Virt = types.Virt;
pub const Size = types.Size;
pub const PageCount = types.PageCount;
pub const Pixels = types.Pixels;
pub const BytesPerRow = types.BytesPerRow;
pub const BitsPerPixel = types.BitsPerPixel;

pub const BOOT_INFO_MAGIC: u64 = 0x4152_4348_4559_5045; // "ARCHEYEP"

pub const MemoryType = enum(u32) {
    usable = 0,
    reserved = 1,
    acpi_reclaimable = 2,
    acpi_nvs = 3,
    bad_memory = 4,
    bootloader_reclaimable = 5,
    kernel = 6,
    _,
};

pub const MemoryRegion = extern struct {
    phys_start: Phys,
    page_count: PageCount,
    mem_type: MemoryType,
    _reserved: u32 = 0,

    pub fn size(self: MemoryRegion) Size {
        return self.page_count.toBytes();
    }

    pub fn physEnd(self: MemoryRegion) Phys {
        return self.phys_start.add(self.size().raw());
    }
};

pub const MemoryMap = extern struct {
    entries: [*]MemoryRegion,
    entry_count: u32,
    _reserved: u32 = 0,

    pub fn slice(self: MemoryMap) []MemoryRegion {
        return self.entries[0..self.entry_count];
    }
};

pub const Framebuffer = extern struct {
    base: Phys,
    size: Size,
    width: Pixels,
    height: Pixels,
    pitch: BytesPerRow,
    bpp: BitsPerPixel,
    _reserved: u16 = 0,
};

/// Boot information passed from logos to kyber.
pub const BootInfo = extern struct {
    magic: u64 = BOOT_INFO_MAGIC,
    entry_phys: Phys,
    entry_virt: Virt,
    kernel_phys_start: Phys,
    kernel_phys_end: Phys,
    cr3: Phys,
    memory_map: MemoryMap,
    framebuffer: ?*Framebuffer,
    rsdp_phys: Phys,

    pub fn validate(self: *const BootInfo) bool {
        return self.magic == BOOT_INFO_MAGIC;
    }

    pub fn kernelSize(self: *const BootInfo) Size {
        return Size.from(self.kernel_phys_end.raw() - self.kernel_phys_start.raw());
    }
};

const testing = @import("std").testing;

test "BootInfo validate with correct magic" {
    var info: BootInfo = undefined;
    info.magic = BOOT_INFO_MAGIC;
    try testing.expect(info.validate());
}

test "BootInfo validate with wrong magic" {
    var info: BootInfo = undefined;
    info.magic = 0;
    try testing.expect(!info.validate());
}

test "BootInfo kernelSize" {
    var info: BootInfo = undefined;
    info.kernel_phys_start = Phys.from(0x10_0000);
    info.kernel_phys_end = Phys.from(0x20_0000);
    try testing.expectEqual(
        @as(u64, 0x10_0000),
        info.kernelSize().raw(),
    );
}

test "MemoryRegion size and physEnd" {
    const region = MemoryRegion{
        .phys_start = Phys.from(0x1000),
        .page_count = PageCount.from(4),
        .mem_type = .usable,
    };
    try testing.expectEqual(@as(u64, 4 * 4096), region.size().raw());
    try testing.expectEqual(
        @as(u64, 0x1000 + 4 * 4096),
        region.physEnd().raw(),
    );
}
