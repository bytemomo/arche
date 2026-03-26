const std = @import("std");
const hal = @import("hal");
const gdt = @import("gdt.zig");
const interrupts = @import("../../interrupts.zig");

// -- Gate Descriptor -------------------------------------------------

pub const GateType = enum(u4) {
    interrupt = 0xE,
    trap = 0xF,
};

pub const Gate = packed struct(u128) {
    offset_low: u16,
    selector: u16,
    ist: u3 = 0,
    _reserved0: u5 = 0,
    gate_type: GateType,
    _reserved1: u1 = 0,
    dpl: u2,
    present: bool = true,
    offset_mid: u16,
    offset_high: u32,
    _reserved2: u32 = 0,

    pub const nil: Gate = @bitCast(@as(u128, 0));

    pub fn from(
        addr: u64,
        sel: u16,
        ist: u3,
        gate_type: GateType,
        dpl: u2,
    ) Gate {
        return .{
            .offset_low = @truncate(addr),
            .selector = sel,
            .ist = ist,
            .gate_type = gate_type,
            .dpl = dpl,
            .offset_mid = @truncate(addr >> 16),
            .offset_high = @truncate(addr >> 32),
        };
    }
};

comptime {
    std.debug.assert(@sizeOf(Gate) == 16);
}

// -- Exception Definitions -------------------------------------------

pub const Exception = struct {
    vector: u8,
    has_error_code: bool,
    gate_type: GateType = .interrupt,
    ist: u3 = 0,
};

pub const EXCEPTIONS = [_]Exception{
    .{ .vector = 0, .has_error_code = false },
    .{ .vector = 1, .has_error_code = false, .gate_type = .trap },
    .{ .vector = 2, .has_error_code = false },
    .{ .vector = 3, .has_error_code = false, .gate_type = .trap },
    .{ .vector = 4, .has_error_code = false },
    .{ .vector = 5, .has_error_code = false },
    .{ .vector = 6, .has_error_code = false },
    .{ .vector = 7, .has_error_code = false },
    .{ .vector = 8, .has_error_code = true, .ist = 1 },
    .{ .vector = 10, .has_error_code = true },
    .{ .vector = 11, .has_error_code = true },
    .{ .vector = 12, .has_error_code = true },
    .{ .vector = 13, .has_error_code = true },
    .{ .vector = 14, .has_error_code = true },
    .{ .vector = 16, .has_error_code = false },
    .{ .vector = 17, .has_error_code = true },
    .{ .vector = 18, .has_error_code = false },
    .{ .vector = 19, .has_error_code = false },
    .{ .vector = 20, .has_error_code = false },
    .{ .vector = 21, .has_error_code = true },
    .{ .vector = 30, .has_error_code = true },
};

comptime {
    for (EXCEPTIONS, 0..) |a, i| {
        for (EXCEPTIONS[i + 1 ..]) |b| {
            if (a.vector == b.vector) @compileError("duplicate vector");
        }
    }
    for (EXCEPTIONS) |exc| {
        if (exc.vector == 8 and exc.ist == 0) {
            @compileError("double fault must use IST");
        }
    }
}

// -- Table -----------------------------------------------------------

const TABLE_LEN = 256;
var table: [TABLE_LEN]Gate align(16) = [_]Gate{Gate.nil} ** TABLE_LEN;

// -- Init ------------------------------------------------------------

pub fn init() void {
    const cs: u16 = @bitCast(gdt.KERNEL_CS);

    hal.idt.install(
        @ptrCast(&table),
        cs,
        EXCEPTIONS,
        &interrupts.dispatch,
    );
}

// -- Inject (for sim) ------------------------------------------------

pub fn inject(vector: u8, error_code: u64) void {
    hal.idt.inject(vector, error_code, &interrupts.dispatch);
}
