const std = @import("std");
const uefi = std.os.uefi;

pub const Console = struct {
    var out: ?*uefi.protocol.SimpleTextOutput = null;

    pub fn init() !void {
        out = uefi.system_table.con_out orelse return error.ConsoleUnavailable;
    }

    pub fn clear() void {
        if (out) |o| {
            _ = o.clearScreen() catch {};
        }
    }

    pub fn writer(buffer: []u8) !Writer {
        const o = out orelse return error.ConsoleNotInitialized;
        return .{
            .context = o,
            .interface = .{
                .buffer = buffer,
                .vtable = &Writer.vtable,
            },
        };
    }

    pub const Writer = struct {
        context: *uefi.protocol.SimpleTextOutput,
        interface: std.Io.Writer,

        const vtable: std.Io.Writer.VTable = .{
            .drain = drain,
        };

        fn drain(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) !usize {
            const self: *@This() = @fieldParentPtr("interface", io_w);
            var total_len: usize = 0;

            for (data[0 .. data.len - 1]) |slice| {
                try self.writeBytes(slice);
                total_len += slice.len;
            }

            const last = data[data.len - 1];
            for (0..splat) |_| {
                try self.writeBytes(last);
                total_len += last.len;
            }

            return total_len;
        }

        fn writeBytes(self: *@This(), bytes: []const u8) !void {
            var buf: [128]u16 = undefined;
            var i: usize = 0;

            for (bytes) |b| {
                buf[i] = b;
                i += 1;

                if (i >= buf.len - 1 or b == '\n') {
                    buf[i] = 0;
                    _ = self.context.outputString(@ptrCast(&buf)) catch {};
                    i = 0;
                }
            }

            if (i > 0) {
                buf[i] = 0;
                _ = self.context.outputString(@ptrCast(&buf)) catch {};
            }
        }
    };
};
