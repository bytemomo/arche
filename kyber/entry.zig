const std = @import("std");
const boot_info = @import("boot_info");
const BootInfo = boot_info.BootInfo;
const gdt = @import("arch/x86_64/gdt.zig");
const idt = @import("arch/x86_64/idt.zig");
const log = @import("log");

pub const std_options: std.Options = .{
    .logFn = log.logFn,
};

const klog = std.log.scoped(.kyber);

export fn _start(info: *BootInfo) callconv(.c) noreturn {
    _ = info;
    log.init() catch {};
    klog.info("kernel started", .{});

    gdt.init();
    klog.info("GDT loaded", .{});

    idt.init();
    klog.info("IDT loaded", .{});

    while (true) {
        asm volatile ("hlt");
    }
}
