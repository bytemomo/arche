const gdt = @import("gdt.zig");
const idt = @import("idt.zig");

pub fn init() void {
    gdt.init();
    idt.init();
}
