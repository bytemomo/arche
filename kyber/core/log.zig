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

pub fn fatal(
    comptime src: std.builtin.SourceLocation,
    comptime msg: []const u8,
) noreturn {
    @branchHint(.cold);
    doLog("[FTL] ", src, msg, .{});
    @panic(msg);
}

pub fn err(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    doLog("[ERR] ", src, fmt, args);
}

pub fn warn(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    doLog("[WRN] ", src, fmt, args);
}

pub fn info(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    doLog("[INF] ", src, fmt, args);
}

pub fn debug(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    doLog("[DBG] ", src, fmt, args);
}

pub fn trace(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    doLog("[TRC] ", src, fmt, args);
}

pub fn doLog(
    comptime level_str: []const u8,
    comptime src: std.builtin.SourceLocation,
    comptime fmt: []const u8,
    args: anytype,
) void {
    const scope = comptime scopeFromPath(src.file);
    const file = comptime fileFromPath(src.file);
    const line = comptime uintToStr(src.line);

    var w = serialWriter() catch return;
    std.Io.Writer.print(
        &w.interface,
        level_str ++ scope ++ " " ++
            file ++ ":" ++ line ++ " " ++ fmt ++ "\n",
        args,
    ) catch {};
}

/// Write raw bytes to serial. Used by the panic handler for
/// runtime (non-comptime) messages.
pub fn writeSerial(bytes: []const u8) void {
    for (bytes) |b| {
        while ((port_io.inb(COM1 + 5) & 0x20) == 0) {}
        port_io.outb(COM1, b);
    }
}

/// Write a usize as decimal to serial.
/// Avoids software division (not available in freestanding)
/// by using repeated subtraction with power-of-10 table.
pub fn writeSerialDec(value: usize) void {
    if (value == 0) {
        writeSerial("0");
        return;
    }

    const powers = [_]usize{
        10_000_000_000_000_000_000,
        1_000_000_000_000_000_000,
        100_000_000_000_000_000,
        10_000_000_000_000_000,
        1_000_000_000_000_000,
        100_000_000_000_000,
        10_000_000_000_000,
        1_000_000_000_000,
        100_000_000_000,
        10_000_000_000,
        1_000_000_000,
        100_000_000,
        10_000_000,
        1_000_000,
        100_000,
        10_000,
        1_000,
        100,
        10,
        1,
    };

    var started = false;
    var v = value;
    for (powers) |p| {
        var digit: u8 = 0;
        while (v >= p) {
            v -= p;
            digit += 1;
        }
        if (digit > 0 or started) {
            started = true;
            writeSerial(&[1]u8{'0' + digit});
        }
    }
}

/// Write a usize as hex to serial.
pub fn writeSerialHex(addr: usize) void {
    writeSerial("0x");
    const hex = "0123456789abcdef";
    var i: u6 = 60;
    while (true) {
        const nibble: u4 = @truncate(addr >> i);
        writeSerial(&[1]u8{hex[nibble]});
        if (i == 0) break;
        i -= 4;
    }
}

pub fn uintToStr(comptime n: u32) []const u8 {
    comptime {
        if (n == 0) return "0";
        var buf: [10]u8 = undefined;
        var len: usize = 0;
        var v = n;
        while (v > 0) {
            buf[len] = '0' + @as(u8, @intCast(v % 10));
            len += 1;
            v /= 10;
        }
        var result: [len]u8 = undefined;
        for (0..len) |i| {
            result[i] = buf[len - 1 - i];
        }
        return &result;
    }
}

pub fn fileFromPath(comptime path: [:0]const u8) []const u8 {
    comptime {
        var i = path.len;
        while (i > 0) {
            i -= 1;
            if (path[i] == '/') return path[i + 1 ..];
        }
        return path;
    }
}

pub fn scopeFromPath(comptime path: [:0]const u8) []const u8 {
    comptime {
        const stripped = if (endsWith(path, ".zig"))
            path[0 .. path.len - 4]
        else
            path[0..path.len];

        const cleaned = removeSegment(
            removeSegment(stripped, "arch/x86_64/"),
            "core/",
        );

        const no_init = if (endsWith(cleaned, "/init"))
            cleaned[0 .. cleaned.len - 5]
        else
            cleaned;

        const scoped = if (no_init.len == 0)
            "kyber"
        else
            "kyber/" ++ no_init;

        return replaceSlashes(scoped);
    }
}

fn endsWith(comptime s: []const u8, comptime suffix: []const u8) bool {
    if (s.len < suffix.len) return false;
    return eql(s[s.len - suffix.len ..], suffix);
}

fn eql(comptime a: []const u8, comptime b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}

fn removeSegment(
    comptime s: []const u8,
    comptime seg: []const u8,
) []const u8 {
    comptime {
        if (s.len < seg.len) return s;
        for (0..s.len - seg.len + 1) |i| {
            if (eql(s[i .. i + seg.len], seg)) {
                var result: [s.len - seg.len]u8 = undefined;
                for (0..i) |j| result[j] = s[j];
                for (i..s.len - seg.len) |j| {
                    result[j] = s[j + seg.len];
                }
                return &result;
            }
        }
        return s;
    }
}

fn replaceSlashes(comptime s: []const u8) []const u8 {
    comptime {
        var slash_count: usize = 0;
        for (s) |c| {
            if (c == '/') slash_count += 1;
        }
        const new_len = s.len + slash_count;
        var result: [new_len]u8 = undefined;
        var j: usize = 0;
        for (s) |c| {
            if (c == '/') {
                result[j] = ':';
                j += 1;
                result[j] = ':';
                j += 1;
            } else {
                result[j] = c;
                j += 1;
            }
        }
        return &result;
    }
}

const SerialWriter = struct {
    interface: std.Io.Writer,

    const vtable: std.Io.Writer.VTable = .{
        .drain = drain,
    };

    fn drain(
        io_w: *std.Io.Writer,
        data: []const []const u8,
        splat: usize,
    ) !usize {
        _ = io_w;
        var total_len: usize = 0;

        for (data[0 .. data.len - 1]) |slice| {
            writeSerial(slice);
            total_len += slice.len;
        }

        const last = data[data.len - 1];
        for (0..splat) |_| {
            writeSerial(last);
            total_len += last.len;
        }

        return total_len;
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
