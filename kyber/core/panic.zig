const std = @import("std");
const hal = @import("hal");
const log = @import("log.zig");

var panicked = false;

/// Zig runtime panic handler. Called by @panic and safety checks.
pub fn call(msg: []const u8, ret_addr: ?usize) noreturn {
    @branchHint(.cold);
    asm volatile ("cli");

    if (panicked) {
        log.writeSerial("[FTL] kyber double panic, halting\n");
        hal.cpu.halt();
    }
    panicked = true;

    log.writeSerial("[FTL] kyber PANIC: ");
    log.writeSerial(msg);
    log.writeSerial("\n");

    // First frame: the return address passed by the runtime,
    // which points to the actual @panic call site.
    if (ret_addr) |ra| {
        writeFrame(0, ra);
    }

    var fp = @frameAddress();
    var depth: usize = 1;
    while (fp != 0 and depth < 16) : (depth += 1) {
        const frame: *const [2]usize = @ptrFromInt(fp);
        const ra = frame[1];
        if (ra == 0) break;
        writeFrame(depth, ra);
        fp = frame[0];
    }

    hal.cpu.halt();
}

fn writeFrame(depth: usize, addr: usize) void {
    log.writeSerial("[FTL]   ");
    log.writeSerialHex(addr);
    if (depth == 0) {
        log.writeSerial(" <-- panic site");
    }
    log.writeSerial("\n");
}

const full = std.debug.FullPanic(call);

pub const sentinelMismatch = full.sentinelMismatch;
pub const unwrapError = full.unwrapError;
pub const outOfBounds = full.outOfBounds;
pub const startGreaterThanEnd = full.startGreaterThanEnd;
pub const inactiveUnionField = full.inactiveUnionField;
pub const sliceCastLenRemainder = full.sliceCastLenRemainder;
pub const reachedUnreachable = full.reachedUnreachable;
pub const unwrapNull = full.unwrapNull;
pub const castToNull = full.castToNull;
pub const incorrectAlignment = full.incorrectAlignment;
pub const invalidErrorCode = full.invalidErrorCode;
pub const integerOutOfBounds = full.integerOutOfBounds;
pub const integerOverflow = full.integerOverflow;
pub const shlOverflow = full.shlOverflow;
pub const shrOverflow = full.shrOverflow;
pub const divideByZero = full.divideByZero;
pub const exactDivisionRemainder = full.exactDivisionRemainder;
pub const integerPartOutOfBounds = full.integerPartOutOfBounds;
pub const corruptSwitch = full.corruptSwitch;
pub const shiftRhsTooBig = full.shiftRhsTooBig;
pub const invalidEnumValue = full.invalidEnumValue;
pub const forLenMismatch = full.forLenMismatch;
pub const copyLenMismatch = full.copyLenMismatch;
pub const memcpyAlias = full.memcpyAlias;
pub const noreturnReturned = full.noreturnReturned;
