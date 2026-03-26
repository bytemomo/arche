const std = @import("std");
const builtin = @import("builtin");
const core = @import("core");
const hal = @import("hal");
const log = @import("log");

const is_wasm = builtin.cpu.arch == .wasm32;

// --- Shared simulation state ---

var sim: core.Simulation = undefined;
var initialized: bool = false;

// --- Tick-based API (exported for wasm host / host runner) ---

export fn sim_init(seed: u64) void {
    sim = core.Simulation.init(seed);
    hal.port_io.init(&sim);
    log.init() catch {};
    initialized = true;
}

export fn sim_step() u64 {
    if (!initialized) return 0;
    sim.step();
    return sim.cycle;
}

export fn sim_event_count() u32 {
    if (!initialized) return 0;
    return @intCast(sim.events.len);
}

export fn sim_log_ptr() [*]const u8 {
    return hal.port_io.getSerialLog().ptr;
}

export fn sim_log_len() u32 {
    return @intCast(hal.port_io.getSerialLog().len);
}

export fn sim_reset() void {
    if (!initialized) return;
    sim.reset();
    hal.port_io.init(&sim);
}

// --- Host-native main (not used in wasm) ---

pub fn main() !void {
    if (is_wasm) return;

    const seed_count: u64 = 100;

    for (0..seed_count) |seed| {
        sim_init(seed);
        for (0..10) |_| {
            _ = sim_step();
        }
    }

    var buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "DST: {d}/{d} seeds passed\n", .{
        seed_count, seed_count,
    }) catch "DST: format error\n";
    std.fs.File.stdout().writeAll(msg) catch {};
}
