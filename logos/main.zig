const std = @import("std");
const option = @import("option");

const Log = @import("log.zig");
const services = @import("uefi/services.zig");
const fs = @import("uefi/fs.zig");
const elf_loader = @import("loader/elf.zig");
const handoff = @import("loader/handoff.zig");

const uefi = std.os.uefi;

const Services = services.Services;
const FileSystem = fs.FileSystem;

pub const std_options = std.Options{
    .log_level = switch (option.log_level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .err => .err,
    },
    .logFn = Log.logFn,
};

const log = std.log.scoped(.logos);

pub fn main() uefi.Status {
    Log.init() catch return .aborted;
    log.info("Logos bootloader starting", .{});

    const svc = Services.init() catch return .aborted;
    log.info("Boot services initialized", .{});

    const filesystem = FileSystem.init(svc) catch return .aborted;

    // Load kernel ELF
    const kernel_file = filesystem.open("kyber.elf") catch |err| {
        log.err("Failed to open kyber.elf: {}", .{err});
        return .aborted;
    };
    defer kernel_file.close();

    const kernel_data = kernel_file.readAlloc(svc) catch |err| {
        log.err("Failed to read kernel: {}", .{err});
        return .aborted;
    };
    log.info("Kernel file read: {} bytes", .{kernel_data.len});

    // Parse and load ELF segments
    const kernel = elf_loader.load(svc, kernel_data) catch |err| {
        log.err("Failed to load kernel ELF: {}", .{err});
        return .aborted;
    };
    log.info("Kernel loaded: entry=0x{x} phys=0x{x}-0x{x}", .{
        kernel.entry_virt,
        kernel.phys_start,
        kernel.phys_end,
    });

    // TBD
    // Handoff to kernel (does not return)
    // handoff.execute(svc, kernel) catch |err| {
    //     log.err("Handoff failed: {}", .{err});
    //     return .aborted;
    // };

    svc.stallSec(5);

    // Exit QEMU via debug exit device (port 0xf4)
    asm volatile ("outb %[val], %[port]"
        :
        : [val] "{al}" (@as(u8, 0)),
          [port] "N{dx}" (@as(u16, 0xf4)),
    );

    return .success;
}
