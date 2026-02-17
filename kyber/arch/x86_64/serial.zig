const std = @import("std");

pub const init = Serial.init;
pub const writer = Serial.writer;

const Serial = struct {
    const COM1: u16 = 0x3F8;

    pub fn init() !void {
        outb(COM1 + 1, 0x00); // Disable interrupts
        outb(COM1 + 3, 0x80); // Enable DLAB (set baud rate divisor)
        outb(COM1 + 0, 0x03); // Divisor low byte (38400 baud)
        outb(COM1 + 1, 0x00); // Divisor high byte
        outb(COM1 + 3, 0x03); // 8 bits, no parity, one stop bit
        outb(COM1 + 2, 0xC7); // Enable FIFO, clear, 14-byte threshold
        outb(COM1 + 4, 0x0B); // IRQs enabled, RTS/DSR set
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
                outb(COM1, b);
            }
        }
    };

    fn waitTxEmpty() void {
        while ((inb(COM1 + 5) & 0x20) == 0) {}
    }

    fn outb(port: u16, value: u8) void {
        asm volatile ("outb %[value], %[port]"
            :
            : [value] "{al}" (value),
              [port] "N{dx}" (port),
        );
    }

    fn inb(port: u16) u8 {
        return asm volatile ("inb %[port], %[result]"
            : [result] "={al}" (-> u8),
            : [port] "N{dx}" (port),
        );
    }
};
