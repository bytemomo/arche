const std = @import("std");
const hal = @import("hal");
const gdt = @import("gdt.zig");
const interrupts = @import("../../core/interrupts.zig");


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


pub const Vector = enum(u8) {
    divide_error = 0,
    debug = 1,
    nmi = 2,
    breakpoint = 3,
    overflow = 4,
    bound_range = 5,
    invalid_opcode = 6,
    device_not_avail = 7,
    double_fault = 8,
    // 9: reserved (coprocessor segment overrun)
    invalid_tss = 10,
    segment_not_present = 11,
    stack_segment = 12,
    general_protection = 13,
    page_fault = 14,
    // 15: reserved
    x87_fp = 16,
    alignment_check = 17,
    machine_check = 18,
    simd_fp = 19,
    virtualization = 20,
    control_protection = 21,
    // 22-27: reserved
    // 28: hypervisor injection
    // 29: vmm communication
    security = 30,
    // 31: reserved

    pub fn hasErrorCode(self: Vector) bool {
        return switch (self) {
            .double_fault,
            .invalid_tss,
            .segment_not_present,
            .stack_segment,
            .general_protection,
            .page_fault,
            .alignment_check,
            .control_protection,
            .security,
            => true,
            else => false,
        };
    }
};

pub const Exception = struct {
    vector: Vector,
    gate_type: GateType = .interrupt,
    ist: u3 = 0,
};

pub const EXCEPTIONS = [_]Exception{
    .{ .vector = .divide_error },
    .{ .vector = .debug, .gate_type = .trap },
    .{ .vector = .nmi },
    .{ .vector = .breakpoint, .gate_type = .trap },
    .{ .vector = .overflow },
    .{ .vector = .bound_range },
    .{ .vector = .invalid_opcode },
    .{ .vector = .device_not_avail },
    .{ .vector = .double_fault, .ist = 1 },
    .{ .vector = .invalid_tss },
    .{ .vector = .segment_not_present },
    .{ .vector = .stack_segment },
    .{ .vector = .general_protection },
    .{ .vector = .page_fault },
    .{ .vector = .x87_fp },
    .{ .vector = .alignment_check },
    .{ .vector = .machine_check },
    .{ .vector = .simd_fp },
    .{ .vector = .virtualization },
    .{ .vector = .control_protection },
    .{ .vector = .security },
};

comptime {
    for (EXCEPTIONS, 0..) |a, i| {
        for (EXCEPTIONS[i + 1 ..]) |b| {
            if (a.vector == b.vector) @compileError("duplicate vector");
        }
    }
    for (EXCEPTIONS) |exc| {
        if (exc.vector == .double_fault and exc.ist == 0) {
            @compileError("double fault must use IST");
        }
    }
}


pub const TABLE_LEN = 256;
var table: [TABLE_LEN]Gate align(16) = [_]Gate{Gate.nil} ** TABLE_LEN;


pub fn init() void {
    const cs: u16 = @bitCast(gdt.KERNEL_CS);

    hal.idt.install(
        @ptrCast(&table),
        cs,
        EXCEPTIONS,
        &interrupts.dispatch,
    );
}


pub fn inject(vector: u8, error_code: u64) void {
    hal.idt.inject(vector, error_code, &interrupts.dispatch);
}
