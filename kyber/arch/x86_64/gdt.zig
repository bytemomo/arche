const std = @import("std");
const cpu = @import("hal").cpu;

pub const Selector = packed struct(u16) {
    rpl: u2,
    table: enum(u1) { gdt = 0, ldt = 1 } = .gdt,
    index: u13,
};

// -- Segment Descriptors ---------------------------------------------

const Access = packed struct(u8) {
    accessed: bool = false,
    /// Code: readable. Data: writable.
    rw: bool,
    /// Code: conforming. Data: direction (0 = grow up).
    dc: bool = false,
    /// 1 = code, 0 = data.
    executable: bool,
    /// 1 = code/data, 0 = system (TSS/LDT).
    descriptor: bool = true,
    /// Descriptor Privilege Level: ring level that the segment belongs to.
    dpl: u2,
    /// Whether the segment is valid and loaded in memory.
    present: bool = true,
};

const Flags = packed struct(u4) {
    reserved: u1 = 0,
    /// 64-bit code segment. Must be 0 for data segments.
    long_mode: bool,
    /// 32-bit segment. Must be 0 when long_mode is set.
    size: bool,
    /// Limit granularity: 0 = byte, 1 = 4 KiB pages.
    granularity: bool = true,
};

const Entry = packed struct(u64) {
    limit_low: u16,
    base_low: u16,
    base_mid: u8,
    access: u8,
    limit_high: u4,
    flags: Flags,
    base_high: u8,

    const nil: Entry = @bitCast(@as(u64, 0));
};

const Descriptor = struct {
    access: Access,
    flags: Flags,

    fn toEntry(comptime self: Descriptor) Entry {
        if (self.flags.long_mode and self.flags.size) {
            @compileError(
                "long_mode and size cannot both be set",
            );
        }
        if (self.access.executable and !self.access.rw) {
            @compileError(
                "code segments should be readable",
            );
        }
        return .{
            .limit_low = 0xFFFF,
            .base_low = 0,
            .base_mid = 0,
            .access = @bitCast(self.access),
            .limit_high = 0xF,
            .flags = self.flags,
            .base_high = 0,
        };
    }
};

comptime {
    std.debug.assert(@sizeOf(Entry) == 8);
}

// -- TSS -------------------------------------------------------------

const Tss = packed struct(u832) {
    _reserved0: u32 = 0,
    rsp0: u64 = 0,
    rsp1: u64 = 0,
    rsp2: u64 = 0,
    _reserved1: u64 = 0,
    ist1: u64 = 0,
    ist2: u64 = 0,
    ist3: u64 = 0,
    ist4: u64 = 0,
    ist5: u64 = 0,
    ist6: u64 = 0,
    ist7: u64 = 0,
    _reserved2: u64 = 0,
    _reserved3: u16 = 0,
    iopb: u16 = @bitSizeOf(Tss) / 8,
};

const TssEntry = packed struct(u128) {
    limit_low: u16,
    base_low: u24,
    type: u4 = 0b1001, // 64-bit available TSS
    descriptor: u1 = 0, // system segment
    dpl: u2 = 0,
    present: bool = true,
    limit_high: u4,
    avl: u1 = 0,
    long: bool = true,
    db: u1 = 0,
    granularity: u1 = 0,
    base_high: u40,
    _reserved: u32 = 0,

    fn new(base: u64, limit: u20) TssEntry {
        return .{
            .limit_low = @truncate(limit),
            .base_low = @truncate(base),
            .limit_high = @truncate(limit >> 16),
            .base_high = @truncate(base >> 24),
        };
    }
};

comptime {
    std.debug.assert(@bitSizeOf(Tss) / 8 == 104);
    std.debug.assert(@sizeOf(TssEntry) == 16);
}

// -- GDT Layout ------------------------------------------------------

const Slot = enum {
    nil,
    kernel_code,
    kernel_data,
    user_data,
    user_code,
    tss,
};

const layout = .{
    .{ Slot.nil, 0, null },
    .{ Slot.kernel_code, 0, Descriptor{
        .access = .{ .rw = true, .executable = true, .dpl = 0 },
        .flags = .{ .long_mode = true, .size = false },
    } },
    .{ Slot.kernel_data, 0, Descriptor{
        .access = .{ .rw = true, .executable = false, .dpl = 0 },
        .flags = .{ .long_mode = false, .size = true },
    } },
    .{ Slot.user_data, 3, Descriptor{
        .access = .{ .rw = true, .executable = false, .dpl = 3 },
        .flags = .{ .long_mode = false, .size = true },
    } },
    .{ Slot.user_code, 3, Descriptor{
        .access = .{ .rw = true, .executable = true, .dpl = 3 },
        .flags = .{ .long_mode = true, .size = false },
    } },
    .{ Slot.tss, 0, null }, // 128-bit TSS spans this + next slot
    .{ Slot.nil, 0, null },
};

fn slotSelector(comptime slot: Slot) Selector {
    for (layout, 0..) |row, i| {
        if (row[0] == slot) {
            return .{ .rpl = row[1], .index = @intCast(i) };
        }
    }
    @compileError("slot not found in layout");
}

fn slotIndex(comptime slot: Slot) comptime_int {
    for (layout, 0..) |row, i| {
        if (row[0] == slot) return i;
    }
    @compileError("slot not found in layout");
}

const table_len = layout.len;

fn buildTable() [table_len]Entry {
    var entries: [table_len]Entry = undefined;
    for (layout, 0..) |row, i| {
        entries[i] = if (@TypeOf(row[2]) == Descriptor)
            row[2].toEntry()
        else
            Entry.nil;
    }
    return entries;
}

pub const KERNEL_CS: Selector = slotSelector(.kernel_code);
pub const KERNEL_DS: Selector = slotSelector(.kernel_data);
pub const USER_CS: Selector = slotSelector(.user_code);
pub const USER_DS: Selector = slotSelector(.user_data);
pub const TSS_SEL: Selector = slotSelector(.tss);

comptime {
    for (layout) |row| {
        if (@TypeOf(row[2]) == Descriptor) {
            if (row[1] != row[2].access.dpl) {
                @compileError(
                    "selector RPL must match descriptor DPL",
                );
            }
        }
    }
    // TSS must have room for 2 slots.
    const tss_idx = slotIndex(.tss);
    if (tss_idx + 1 >= table_len) {
        @compileError("TSS needs two consecutive GDT slots");
    }
}

// -- Runtime State ---------------------------------------------------

var tss: Tss = .{};
var table align(16) = buildTable();

// -- Load Helpers ----------------------------------------------------

fn loadTss() void {
    const tss_idx = comptime slotIndex(.tss);
    const base = @intFromPtr(&tss);
    const limit: u20 = @bitSizeOf(Tss) / 8 - 1;
    const desc: u128 = @bitCast(TssEntry.new(base, limit));
    table[tss_idx] = @bitCast(@as(u64, @truncate(desc)));
    table[tss_idx + 1] = @bitCast(@as(u64, @truncate(desc >> 64)));

    cpu.ltr(@bitCast(TSS_SEL));
}

// -- Init ------------------------------------------------------------

pub fn init() void {
    cpu.lgdt(@intFromPtr(&table), @sizeOf(@TypeOf(table)) - 1);
    cpu.loadCs(@bitCast(KERNEL_CS));
    cpu.loadDs(@bitCast(KERNEL_DS));
    loadTss();
}
