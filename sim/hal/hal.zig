pub const port_io = @import("port_io.zig");
pub const cpu = @import("cpu.zig");
pub const idt = @import("idt.zig");

comptime {
    _ = port_io;
}
