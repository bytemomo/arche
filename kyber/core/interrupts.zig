const log = @import("log.zig");

pub const MAX_VECTORS = 256;
pub const Handler = *const fn (vector: u8, error_code: u64) void;

var handlers: [MAX_VECTORS]Handler = [_]Handler{unhandled} ** MAX_VECTORS;

pub fn register(vector: u8, h: Handler) void {
    handlers[vector] = h;
}

pub fn dispatch(vector: u8, error_code: u64) void {
    handlers[vector](vector, error_code);
}

fn unhandled(vector: u8, error_code: u64) void {
    const hal_idt = @import("hal").idt;
    const rip = hal_idt.lastRip();
    log.writeSerial("\n!!! UNHANDLED EXCEPTION vec=");
    log.writeSerialDec(vector);
    log.writeSerial(" err=0x");
    log.writeSerialHex(error_code);
    log.writeSerial(" RIP=0x");
    log.writeSerialHex(rip);
    log.writeSerial(" CS=0x");
    log.writeSerialHex(hal_idt.lastCs());
    log.writeSerial(" RFLAGS=0x");
    log.writeSerialHex(hal_idt.lastRflags());
    log.writeSerial("\n  faulting bytes:");
    const p: [*]const u8 = @ptrFromInt(rip);
    for (0..16) |i| {
        log.writeSerial(" ");
        log.writeSerialHex(@as(u64, p[i]));
    }
    log.writeSerial("\n");
    while (true) asm volatile ("hlt");
}
