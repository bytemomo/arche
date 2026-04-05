const hal = @import("hal");
pub const arch = @import("arch");

comptime {
    _ = arch.exports;
}

const core = @import("core");
const log = core.log;
pub const boot_info = core.boot_info;
pub const types = core.types;
pub const panic = core.panic;

/// Arch-independent kernel entry point.
pub fn kmain() noreturn {
    log.info(@src(), "running on kernel stack", .{});
    hal.cpu.halt();
}
