const std = @import("std");
const builtin = @import("builtin");
const core = @import("core");
const hal = @import("hal");
const kernel = @import("kernel");

const boot_info = kernel.boot_info;
const types = kernel.types;
const Phys = types.Phys;
const Virt = types.Virt;
const PageCount = types.PageCount;

const is_wasm = builtin.cpu.arch == .wasm32;

var sim: core.Simulation = undefined;

var regions = [_]boot_info.MemoryRegion{.{
    .phys_start = Phys.from(0),
    .page_count = PageCount.from(65536),
    .mem_type = .usable,
}};

var info = boot_info.BootInfo{
    .entry_phys = Phys.from(0x20_0000),
    .entry_virt = Virt.from(0xFFFF_C000_0020_0000),
    .kernel_phys_start = Phys.from(0x20_0000),
    .kernel_phys_end = Phys.from(0x40_0000),
    .cr3 = Phys.from(0x1000),
    .memory_map = .{
        .entries = &regions,
        .entry_count = 1,
    },
    .framebuffer = null,
    .rsdp_phys = Phys.from(0),
};


export fn sim_init(seed: u64) void {
    sim = core.Simulation.init(seed);
    hal.port_io.init(&sim);
    kernel.init(&info);
}

export fn sim_step() u64 {
    sim.step();
    return sim.cycle;
}

export fn sim_event_count() u32 {
    return @intCast(sim.events.len);
}

export fn sim_log_ptr() [*]const u8 {
    return hal.port_io.getSerialLog().ptr;
}

export fn sim_log_len() u32 {
    return @intCast(hal.port_io.getSerialLog().len);
}

export fn sim_reset() void {
    sim.reset();
    hal.port_io.init(&sim);
}


pub fn main() !void {
    if (is_wasm) return;

    const seed_count: u64 = 100;

    for (0..seed_count) |seed| {
        sim_init(seed);
        for (0..10) |_| {
            _ = sim_step();
        }
    }

    const serial_log = hal.port_io.getSerialLog();
    if (serial_log.len > 0) {
        std.fs.File.stdout().writeAll(serial_log) catch {};
    }

    var buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "DST: {d}/{d} seeds passed\n", .{
        seed_count, seed_count,
    }) catch "DST: format error\n";
    std.fs.File.stdout().writeAll(msg) catch {};
}
