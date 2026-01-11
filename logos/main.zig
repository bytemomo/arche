const std = @import("std");
const option = @import("option");
const Log = @import("log.zig");

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
    const con_out = uefi.system_table.con_out orelse return .aborted;
    Console.init(con_out);

    Console.clear_screen();
    log.info("Hello world from Zig UEFI!", .{});

    if (uefi.system_table.boot_services) |boot_services| {
        _ = boot_services.stall(5 * 1000 * 1000) catch {};
    }

    return .success;
}
