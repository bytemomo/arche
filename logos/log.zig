const std = @import("std");
const Console = @import("uefi/console.zig").Console;

pub fn init() !void {
    try Console.init();
    Console.clear();
}

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_str = comptime switch (level) {
        .debug => "[DBG ]",
        .info => "[INFO]",
        .warn => "[WARN]",
        .err => "[ERR ]",
    };
    const scope_str = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    var writer = Console.writer(&.{}) catch return;
    std.Io.Writer.print(&writer.interface, level_str ++ " " ++ scope_str ++ format ++ "\r\n", args) catch {};
}
