const std = @import("std");
const port_io = @import("hal").port_io;

const COM1: u16 = 0x3F8;

pub fn init() !void {
    port_io.outb(COM1 + 1, 0x00);
    port_io.outb(COM1 + 3, 0x80);
    port_io.outb(COM1 + 0, 0x03);
    port_io.outb(COM1 + 1, 0x00);
    port_io.outb(COM1 + 3, 0x03);
    port_io.outb(COM1 + 2, 0xC7);
    port_io.outb(COM1 + 4, 0x0B);
}

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_str = comptime switch (level) {
        .debug => "[DBG]",
        .info => "[INF]",
        .warn => "[WRN]",
        .err => "[ERR]",
    };
    const scope_str = if (scope == .default)
        ": "
    else
        "(" ++ comptime formatScope(@tagName(scope)) ++ "): ";

    var w = serialWriter() catch return;
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

const SerialWriter = struct {
    interface: std.Io.Writer,

    const vtable: std.Io.Writer.VTable = .{
        .drain = drain,
    };

    fn drain(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) !usize {
        _ = io_w;
        var total_len: usize = 0;

        for (data[0 .. data.len - 1]) |slice| {
            writeBytes(slice);
            total_len += slice.len;
        }

        const last = data[data.len - 1];
        for (0..splat) |_| {
            writeBytes(last);
            total_len += last.len;
        }

        return total_len;
    }

    fn writeBytes(bytes: []const u8) void {
        for (bytes) |b| {
            while ((port_io.inb(COM1 + 5) & 0x20) == 0) {}
            port_io.outb(COM1, b);
        }
    }
};

fn serialWriter() !SerialWriter {
    return .{
        .interface = .{
            .buffer = &.{},
            .vtable = &SerialWriter.vtable,
        },
    };
}
