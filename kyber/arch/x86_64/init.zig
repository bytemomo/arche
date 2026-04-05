const builtin = @import("builtin");
const mm = @import("mm/init.zig");
const layout = @import("mm/layout.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const hal = @import("hal");

const core = @import("core");
const boot_info = core.boot_info;
const log = core.log;

const kernel = @import("kernel");

pub const MAX_VECTORS = idt.TABLE_LEN;

pub fn init(info: *boot_info.BootInfo) void {
    log.init() catch {};
    log.info(@src(), "kernel started", .{});

    gdt.init();
    idt.init();

    mm.init(info);

    log.info(@src(), "arch initialized", .{});
}

pub fn start(info: *boot_info.BootInfo) callconv(.c) noreturn {
    init(info);

    const stack_top = layout.KERNEL_STACK_BASE.raw() +
        layout.KERNEL_STACK_SIZE.raw();
    hal.cpu.switchStackAndCall(stack_top, &kernel.kmain);
}

pub const exports = if (builtin.os.tag == .freestanding)
    @export(&start, .{ .name = "_start" })
else
    {};
