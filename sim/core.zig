const std = @import("std");

pub const Simulation = struct {
    seed: u64,
    rng: std.Random.Xoshiro256,
    cycle: u64,
    events: EventLog,

    pub fn init(seed: u64) Simulation {
        return .{
            .seed = seed,
            .rng = std.Random.Xoshiro256.init(seed),
            .cycle = 0,
            .events = EventLog.init(),
        };
    }

    pub fn step(self: *Simulation) void {
        self.cycle += 1;
    }

    /// Deterministic choice — same seed + same call sequence = same result.
    pub fn choice(
        self: *Simulation,
        comptime T: type,
        min: T,
        max: T,
    ) T {
        return self.rng.random().intRangeAtMost(T, min, max);
    }

    /// Record an event in the log for replay and inspection.
    pub fn record(self: *Simulation, event: Event) void {
        self.events.append(event);
    }

    pub fn reset(self: *Simulation) void {
        self.rng = std.Random.Xoshiro256.init(self.seed);
        self.cycle = 0;
        self.events.clear();
    }
};

pub const Event = union(enum) {
    port_write: PortEvent,
    port_read: PortEvent,
    alloc: AllocEvent,
    alloc_failure: AllocEvent,
    free: AllocEvent,
    log_msg: LogEvent,

    pub const PortEvent = struct {
        port: u16,
        value: u8,
    };

    pub const AllocEvent = struct {
        addr: u64,
        page_count: u64,
    };

    pub const LogEvent = struct {
        level: u8,
        offset: u32,
        len: u32,
    };
};

/// Fixed-capacity event log that works without heap allocation.
/// Suitable for both host and wasm32 targets.
pub const EventLog = struct {
    buffer: [MAX_EVENTS]Event = undefined,
    len: usize = 0,

    const MAX_EVENTS = 64 * 1024;

    pub fn init() EventLog {
        return .{};
    }

    pub fn append(self: *EventLog, event: Event) void {
        if (self.len < MAX_EVENTS) {
            self.buffer[self.len] = event;
            self.len += 1;
        }
    }

    pub fn clear(self: *EventLog) void {
        self.len = 0;
    }

    pub fn slice(self: *const EventLog) []const Event {
        return self.buffer[0..self.len];
    }
};

const testing = std.testing;

test "deterministic: same seed produces same sequence" {
    var a = Simulation.init(42);
    var b = Simulation.init(42);

    for (0..100) |_| {
        const va = a.choice(u32, 0, 1000);
        const vb = b.choice(u32, 0, 1000);
        try testing.expectEqual(va, vb);
    }
}

test "different seeds produce different sequences" {
    var a = Simulation.init(1);
    var b = Simulation.init(2);

    var differ = false;
    for (0..100) |_| {
        if (a.choice(u32, 0, 1_000_000) != b.choice(u32, 0, 1_000_000)) {
            differ = true;
            break;
        }
    }
    try testing.expect(differ);
}

test "reset replays identical sequence" {
    var sim = Simulation.init(99);
    var first: [50]u32 = undefined;
    for (&first) |*v| {
        v.* = sim.choice(u32, 0, 10_000);
    }

    sim.reset();

    for (first) |expected| {
        try testing.expectEqual(expected, sim.choice(u32, 0, 10_000));
    }
}

test "event log records and clears" {
    var sim = Simulation.init(0);
    sim.record(.{ .port_write = .{ .port = 0x3F8, .value = 0x41 } });
    sim.record(.{ .port_read = .{ .port = 0x3FD, .value = 0x20 } });

    try testing.expectEqual(@as(usize, 2), sim.events.len);
    try testing.expectEqual(@as(u16, 0x3F8), sim.events.slice()[0].port_write.port);

    sim.events.clear();
    try testing.expectEqual(@as(usize, 0), sim.events.len);
}
