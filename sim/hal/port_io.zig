const core = @import("core");

const COM1: u16 = 0x3F8;
const SERIAL_BUF_SIZE = 64 * 1024;

var ports: [65536]u8 = [_]u8{0} ** 65536;
var sim: ?*core.Simulation = null;
var serial_buf: [SERIAL_BUF_SIZE]u8 = undefined;
var serial_len: usize = 0;

pub fn init(s: *core.Simulation) void {
    sim = s;
    ports = [_]u8{0} ** 65536;
    serial_len = 0;
    // Pre-set serial TX-ready bit so waitTxEmpty doesn't spin.
    ports[0x3FD] = 0x20;
}

pub fn outb(port: u16, value: u8) void {
    ports[port] = value;
    if (port == COM1 and serial_len < SERIAL_BUF_SIZE) {
        serial_buf[serial_len] = value;
        serial_len += 1;
    }
    if (sim) |s| {
        s.record(.{ .port_write = .{ .port = port, .value = value } });
    }
}

pub fn getSerialLog() []const u8 {
    return serial_buf[0..serial_len];
}

pub fn inb(port: u16) u8 {
    const value = ports[port];
    if (sim) |s| {
        s.record(.{ .port_read = .{ .port = port, .value = value } });
    }
    return value;
}

/// Pre-set a port value to simulate hardware state.
pub fn set(port: u16, value: u8) void {
    ports[port] = value;
}

/// Read port state without recording an event.
pub fn peek(port: u16) u8 {
    return ports[port];
}

const testing = @import("std").testing;

test "outb stores and inb reads back" {
    var s = core.Simulation.init(0);
    init(&s);

    outb(0x3F8, 0x41);
    const val = inb(0x3F8);

    try testing.expectEqual(@as(u8, 0x41), val);
}

test "port operations are recorded as events" {
    var s = core.Simulation.init(0);
    init(&s);

    outb(0x3F8, 0x42);
    _ = inb(0x3FD);

    const events = s.events.slice();
    try testing.expectEqual(@as(usize, 2), events.len);
    try testing.expectEqual(@as(u16, 0x3F8), events[0].port_write.port);
    try testing.expectEqual(@as(u16, 0x3FD), events[1].port_read.port);
}

test "set pre-loads port value for inb" {
    var s = core.Simulation.init(0);
    init(&s);

    set(0x3FD, 0x20);
    const val = inb(0x3FD);

    try testing.expectEqual(@as(u8, 0x20), val);
}
