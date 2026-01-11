const std = @import("std");
const option = @import("option");
const Log = @import("log.zig");
const sfs = @import("sfs.zig");

const uefi = std.os.uefi;
const Console = Log.UefiConsole;

pub const std_options = std.Options{
    .log_level = switch (option.log_level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .err => .err,
    },
    .logFn = Log.myLogFn,
};
const log = std.log.scoped(.logos);

pub fn main() uefi.Status {
    {
        const con_out = uefi.system_table.con_out orelse return .aborted;

        Console.init(con_out);
        Console.clear_screen();
        log.info("Hello world from Zig UEFI!", .{});
    }


    const boot_service: *uefi.tables.BootServices = uefi.system_table.boot_services orelse {
        log.err("Failed to get boot services.", .{});
        return .aborted;
    };
    log.info("Got boot services.", .{});

    {
        const simplefs = sfs.SFileSystem.init(boot_service) catch return .aborted;
        _ = simplefs.openFile("kyber.elf") catch |err| {
            log.err("Failed to open bootloader.zig: {}", .{err});
            return .aborted;
        };
        log.info("Opened kernel file.", .{});
    }


    _ = boot_service.stall(5 * 1000 * 1000) catch {};

    return .success;
}
