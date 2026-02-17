const std = @import("std");
const boot_info = @import("boot_info");
const BootInfo = boot_info.BootInfo;
const log = @import("log");

pub const std_options: std.Options = .{
    .logFn = log.logFn,
};


const klog = std.log.scoped(.kyber);

export fn _start(info: *BootInfo) callconv(.c) noreturn {
    _ = info;
    log.init() catch {};
    klog.info("kernel started", .{});

    while (true) {
        asm volatile ("hlt");
    }
}
