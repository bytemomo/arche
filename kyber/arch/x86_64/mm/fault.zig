const hal = @import("hal");
const core = @import("core");
const idt = @import("../idt.zig");

const log = core.log;
const intr = core.interrupts;

pub const PageFaultError = packed struct(u32) {
    /// 0 = non-present page, 1 = protection violation.
    present: bool,
    /// 0 = read, 1 = write
    write: bool,
    /// 0 = supervisor, 1 = user
    user: bool,
    /// 1 = reserver bit
    rsvd: bool,
    /// 1 = fault caused by instruction fetch
    instruction_fetch: bool,
    /// 1 = protection key violation
    protection_key: bool,
    /// 1 = shadow stack access
    shadow_stack: bool,
    _reserved: u8 = 0,
    /// 1 = SGX induced
    sgx: bool,
    _reserved2: u16 = 0,
};

fn pageFault(_: u8, raw_error: u64) void {
    const err: PageFaultError = @bitCast(@as(u32, @truncate(raw_error)));
    const cr2 = hal.cpu.readCr2();

    log.writeSerial("\n!!! PAGE FAULT !!!\n  CR2 = 0x");
    log.writeSerialHex(cr2);
    log.writeSerial("\n  cause = ");
    log.writeSerial(if (err.present) "protection" else "not-present");
    log.writeSerial(", ");
    log.writeSerial(if (err.write) "write" else "read");
    log.writeSerial(", ");
    log.writeSerial(if (err.user) "user" else "supervisor");
    if (err.instruction_fetch) log.writeSerial(", insn-fetch");
    if (err.rsvd) log.writeSerial(", reserved-bit");
    log.writeSerial("\n");


    @panic("unhandled page fault");
}


pub fn init() void {
    intr.register(
        @intFromEnum(idt.Vector.page_fault),
        &pageFault
    );
}
