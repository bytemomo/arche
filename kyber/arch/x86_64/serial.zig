const std = @import("std");
const port_io = @import("hal").port_io;

pub const init = Serial.init;
pub const writer = Serial.writer;

const Serial = struct {
    const COM1: u16 = 0x3F8;

    pub fn init() !void {
        port_io.outb(COM1 + 1, 0x00); // Disable interrupts
        port_io.outb(COM1 + 3, 0x80); // Enable DLAB (set baud rate divisor)
        port_io.outb(COM1 + 0, 0x03); // Divisor low byte (38400 baud)
        port_io.outb(COM1 + 1, 0x00); // Divisor high byte
        port_io.outb(COM1 + 3, 0x03); // 8 bits, no parity, one stop bit
        port_io.outb(COM1 + 2, 0xC7); // Enable FIFO, clear, 14-byte threshold
        port_io.outb(COM1 + 4, 0x0B); // IRQs enabled, RTS/DSR set
    }

    pub fn writer() !Writer {
        return .{
            .interface = .{
                .buffer = &.{},
                .vtable = &Writer.vtable,
            },
        };
    }

    pub const Writer = struct {
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
                waitTxEmpty();
                port_io.outb(COM1, b);
            }
        }
    };

    fn waitTxEmpty() void {
        while ((port_io.inb(COM1 + 5) & 0x20) == 0) {}
    }
};
