const std = @import("std");
const Backend = @import("uefi/console.zig");

pub fn init() !void {
    try Backend.init();
}

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_str = comptime switch (level) {
        .debug => "[DBG]",
        .info => "[INF]",
        .warn => "[WRN]",
        .err => "[ERR]",
    };
    const scope_str = if (scope == .default) ": " else "(" ++ comptime formatScope(@tagName(scope)) ++ "): ";

    var w = Backend.writer() catch return;
    std.Io.Writer.print(&w.interface, level_str ++ " " ++ scope_str ++ format ++ "\n", args) catch {};
}

fn formatScope(comptime name: []const u8) []const u8 {
    comptime {
        var result: [name.len]u8 = undefined;
        var i: usize = 0;
        while (i < name.len) {
            if (i + 1 < name.len and name[i] == '_' and name[i + 1] == '_') {
                result[i] = '/';
                i += 1;
                var j: usize = i;
                while (j + 1 < name.len) {
                    result[j] = name[j + 1];
                    j += 1;
                }
                return result[0 .. name.len - 1];
            }
            result[i] = name[i];
            i += 1;
        }
        return result[0..name.len];
    }
}
