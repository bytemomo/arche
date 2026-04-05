const builtin = @import("builtin");
pub const boot_info = @import("core/boot_info.zig");
pub const types = @import("core/types.zig");
const BootInfo = boot_info.BootInfo;
const arch = @import("arch/x86_64/init.zig");
const hal = @import("hal");
const log = @import("core/log.zig");

/// Initialization - called by both the real entry point and the
/// simulator. All kernel setup goes here. The sim imports this module
/// and calls init() directly, running the same code through the sim HAL.
pub fn init(info: *BootInfo) void {
    log.init() catch {};
    log.info(@src(), "kernel started", .{});

    arch.init(info);
    log.info(@src(), "arch initialized", .{});
}

/// Real entry point - calls init then halts. Never returns.
/// Not pub: only exposed via the _start export below.
fn start(info: *BootInfo) callconv(.c) noreturn {
    init(info);
    hal.cpu.halt();
}

// Export _start only on the real kernel target. The sim compiles this
// module too, but on a host/wasm target _start must not be exported
// (it collide with the host's own entry point).
comptime {
    if (builtin.cpu.arch == .x86_64 and builtin.os.tag == .freestanding) {
        @export(&start, .{ .name = "_start" });
    }
}
